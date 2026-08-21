# End-to-End DevOps CI/CD Pipeline — Complete Build Guide (Cost-Optimized)

**Stack:** Jenkins · Docker · Terraform · Ansible · AWS EKS · Prometheus/Grafana
**Design principle:** Every choice below defaults to the cheapest AWS option that still teaches the "real" pattern. Cost callouts are marked 💰.

---

## 0. Cost Strategy (read this first)

| Cost driver | Optimization |
|---|---|
| EKS control plane | Fixed ~$0.10/hr (~$73/mo) — unavoidable if using EKS. Only cost you can't shrink. Run `terraform destroy` whenever you stop working. |
| Worker nodes | Use **Spot** instances (`t3.medium`, 1–2 nodes) via a managed node group with `capacity_type = "SPOT"`. Saves ~60–70% vs on-demand. |
| NAT Gateway | Single NAT gateway (not one per AZ) — saves ~$65/mo. For pure learning, consider a NAT instance (`t3.nano`, ~$3/mo) instead of managed NAT (~$32/mo + data). |
| Jenkins server | `t3.micro`/`t3.small` on Spot, or run Jenkins **inside** the EKS cluster as a pod instead of a dedicated EC2 — removes a whole line item. |
| ECR | Free tier: 500MB/month storage. Set lifecycle policy to expire untagged images after 3 days. |
| Prometheus/Grafana | Self-hosted via Helm on the same cluster (not AWS Managed Prometheus/Grafana, which bills separately). |
| CloudWatch | Keep log retention short (3–7 days) to avoid storage creep. |
| Idle time | **The #1 cost lever**: `terraform destroy` at the end of every session. Nothing here needs to run 24/7 for a learning project. |
| Budget guardrail | Set an AWS Budget alert at $20 and $50 on day one, before provisioning anything. |

Set the budget alert now:
```bash
aws budgets create-budget --account-id <ACCOUNT_ID> --budget '{
  "BudgetName": "devops-project-budget",
  "BudgetLimit": {"Amount": "50", "Unit": "USD"},
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}'
```

---

## Sprint 1 — Architecture, Dockerization, Jenkins Setup

### 1.1 Architecture (cost-optimized version)
- Single AZ pair (2 AZs minimum for EKS, not 3) — fewer subnets, fewer NAT paths.
- One managed node group, Spot, `t3.medium`, min=1 / desired=1 / max=3 (autoscaling only under load).
- Jenkins runs as a pod in-cluster (avoids a second EC2 bill) OR on a single `t3.small` Spot instance if you want it isolated from the cluster it manages.
- ALB Ingress Controller for the app instead of a separate Classic/NLB per service — one load balancer shared across services via path/host routing.

### 1.2 Dockerfile (example Node/Python-agnostic pattern)
```dockerfile
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=build /app ./
EXPOSE 3000
USER node
CMD ["node", "server.js"]
```
💰 Multi-stage build keeps the final image small — smaller images = faster pulls = less data transfer cost, and less ECR storage.

### 1.3 Push to ECR with a lifecycle policy
```bash
aws ecr create-repository --repository-name myapp
aws ecr put-lifecycle-policy --repository-name myapp --lifecycle-policy-text '{
  "rules": [{"rulePriority":1,"description":"Expire untagged >3 days",
  "selection":{"tagStatus":"untagged","countType":"sinceImagePushed","countUnit":"days","countNumber":3},
  "action":{"type":"expire"}}]}'
```

### 1.4 Jenkins on a Spot EC2 (minimal footprint)
```bash
aws ec2 request-spot-instances --instance-count 1 \
  --launch-specification '{
    "ImageId":"ami-0xxxxxxx",
    "InstanceType":"t3.small",
    "SecurityGroupIds":["sg-xxxx"],
    "KeyName":"jenkins-key"
  }'
```
Install Jenkins via the Ansible playbook in Sprint 3 rather than baking a custom AMI — keeps this step free of extra image-storage cost.

Required plugins: **Docker Pipeline, Kubernetes, AWS Credentials, Pipeline: AWS Steps**.

---

## Sprint 2 — Terraform: VPC, EKS, Networking

### 2.1 State backend (S3 + DynamoDB lock) — set this up first
```hcl
terraform {
  backend "s3" {
    bucket         = "capstone-tfstate-<unique-suffix>"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}
```
💰 An S3 bucket + on-demand DynamoDB table for locking costs pennies — always cheaper than losing state.

### 2.2 VPC — 2 AZs, single NAT
```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "devops-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true   # 💰 one NAT instead of one per AZ
  one_nat_gateway_per_az = false

  tags = { "kubernetes.io/cluster/devops-eks" = "shared" }
}
```

### 2.3 EKS cluster — Spot node group
```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "devops-eks"
  cluster_version = "1.29"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      capacity_type  = "SPOT"      # 💰 60-70% cheaper than on-demand
      min_size       = 1
      max_size       = 3
      desired_size   = 1
    }
  }
}
```

### 2.4 Jenkins job: `terraform-provision`
```groovy
pipeline {
  agent any
  stages {
    stage('Init')  { steps { sh 'terraform init' } }
    stage('Plan')  { steps { sh 'terraform plan -out=tfplan' } }
    stage('Apply') { steps { sh 'terraform apply -auto-approve tfplan' } }
  }
}
```
Gate `Apply` behind a manual approval input step in a shared, cost-sensitive environment.

---

## Sprint 3 — Ansible Configuration Management

### 3.1 Inventory + playbook: install Docker, kubectl, AWS CLI
```yaml
# playbook.yml
- hosts: jenkins_and_nodes
  become: true
  tasks:
    - name: Install Docker
      apt: { name: docker.io, state: present, update_cache: true }
    - name: Install kubectl
      get_url:
        url: https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl
        dest: /usr/local/bin/kubectl
        mode: '0755'
    - name: Install AWS CLI v2
      shell: |
        curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
        unzip -o awscliv2.zip && ./aws/install
```

### 3.2 Jenkins job: `ansible-configure` (triggered after Terraform)
```groovy
pipeline {
  agent any
  triggers { upstream(upstreamProjects: 'terraform-provision', threshold: hudson.model.Result.SUCCESS) }
  stages {
    stage('Configure') { steps { sh 'ansible-playbook -i inventory.ini playbook.yml' } }
  }
}
```

---

## Sprint 4 — CI/CD Pipeline: Build → Deploy to EKS

### 4.1 Full Jenkinsfile
```groovy
pipeline {
  agent any
  environment {
    ECR_REPO = "1234567890.dkr.ecr.us-east-1.amazonaws.com/myapp"
    IMAGE_TAG = "${env.BUILD_NUMBER}"
  }
  stages {
    stage('Build')  { steps { sh 'docker build -t $ECR_REPO:$IMAGE_TAG .' } }
    stage('Test')   { steps { sh 'docker run --rm $ECR_REPO:$IMAGE_TAG npm test' } }
    stage('Push') {
      steps {
        sh '''
          aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REPO
          docker push $ECR_REPO:$IMAGE_TAG
        '''
      }
    }
    stage('Deploy') {
      steps {
        sh '''
          sed -i "s|IMAGE_PLACEHOLDER|$ECR_REPO:$IMAGE_TAG|" k8s/deployment.yaml
          kubectl apply -f k8s/deployment.yaml
          kubectl apply -f k8s/service.yaml
          kubectl apply -f k8s/hpa.yaml
        '''
      }
    }
  }
}
```

### 4.2 Kubernetes manifests (with autoscaling, not a fixed large replica count)
```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: myapp }
spec:
  replicas: 1   # 💰 start at 1; let HPA scale, don't pre-provision capacity
  selector: { matchLabels: { app: myapp } }
  template:
    metadata: { labels: { app: myapp } }
    spec:
      containers:
        - name: myapp
          image: IMAGE_PLACEHOLDER
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits:   { cpu: "250m", memory: "256Mi" }
          readinessProbe: { httpGet: { path: /health, port: 3000 }, initialDelaySeconds: 5 }
          livenessProbe:  { httpGet: { path: /health, port: 3000 }, initialDelaySeconds: 10 }
```
```yaml
# hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: myapp-hpa }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: myapp }
  minReplicas: 1
  maxReplicas: 4
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
```
💰 Setting real `requests`/`limits` (not defaults) prevents over-scheduling nodes, which is what silently drives up your EC2 bill.

---

## Sprint 5 — Monitoring: Prometheus + Grafana (self-hosted, not AWS-managed)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.persistence.enabled=false \
  --set prometheus.prometheusSpec.retention=3d
```
💰 `persistence.enabled=false` and a short retention window avoid provisioning extra EBS volumes for a learning project. Turn persistence on only if you need dashboards to survive pod restarts long-term.

Alerting rule example (failed deployment):
```yaml
groups:
  - name: deployment-alerts
    rules:
      - alert: DeploymentReplicasMismatch
        expr: kube_deployment_spec_replicas != kube_deployment_status_replicas_available
        for: 5m
        labels: { severity: critical }
        annotations: { summary: "Deployment replica mismatch" }
```
Wire Jenkins notifications via a webhook step in the pipeline (Slack/email plugin) triggered on `post { failure { ... } }`.

---

## Sprint 6 — Testing, Documentation, Final Automation

- **Tests:** smoke test with `curl`/`kubectl rollout status` post-deploy; add to the `Deploy` stage as a final verification step so a bad rollout fails the build instead of silently succeeding.
- **Documentation:** one `README.md` per tool (`terraform/README.md`, `ansible/README.md`, `jenkins/README.md`) covering setup, teardown, and troubleshooting — this satisfies the 15% documentation weight directly.
- **Triggers:** wire `code push → Build job → Terraform job (only if infra changed) → Ansible job → Deploy job` using upstream/downstream Jenkins triggers, not separate manual runs.
- **Final review:** run the teardown script below, then a clean `terraform apply` from scratch to prove the pipeline is fully reproducible — this is the strongest evidence for the 75% implementation weight.

---

## Teardown Checklist (run after every work session)

```bash
kubectl delete -f k8s/                     # remove workloads first
helm uninstall monitoring -n monitoring     # remove Prometheus/Grafana
terraform destroy -auto-approve             # tear down VPC/EKS/NAT
# Verify nothing billable remains:
aws eks list-clusters
aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"
aws elbv2 describe-load-balancers
```
Leaving an EKS cluster + NAT + Spot node running idle overnight is the single most common way this project blows past a "cost-optimized" budget — that checklist is worth automating as a Jenkins job too.

---

## Approximate Monthly Cost (if run continuously, worst case vs. optimized)

| Component | Always-on | This guide's setup |
|---|---|---|
| EKS control plane | $73 | $73 (unavoidable) |
| Worker nodes (2× t3.medium) | ~$60 on-demand | ~$20 (1 node, Spot) |
| NAT Gateway | $65 (3 AZs) | $32 (1 AZ) or ~$3 (NAT instance) |
| Jenkins EC2 | $15 (t3.small on-demand) | ~$5 (Spot) or $0 (in-cluster pod) |
| EBS/storage | ~$10 | ~$2 (no Grafana persistence) |
| **Total** | **~$223/mo** | **~$100/mo running 24/7, near $0 when torn down between sessions** |

The biggest lever isn't any single line item — it's **not leaving the cluster up when you're not actively working**.
