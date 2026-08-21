# Exposing a Local Jenkins to GitHub via ngrok

Use this if Jenkins is running on your laptop or a local VM (no public IP), so
GitHub can still reach it to trigger builds via webhook. This is also the
cheapest option overall — $0 in AWS EC2 cost for Jenkins itself.

## 1. Run Jenkins locally
```bash
docker run -d --name jenkins -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts
```
Get the initial admin password:
```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

## 2. Install and authenticate ngrok
```bash
# Linux example — see ngrok.com/download for other OSes
curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
sudo apt update && sudo apt install ngrok

ngrok config add-authtoken <YOUR_NGROK_AUTHTOKEN>   # from dashboard.ngrok.com
```

## 3. Expose Jenkins port 8080
```bash
ngrok http 8080
```
ngrok prints a forwarding URL like:
```
Forwarding   https://a1b2-34-56-78-90.ngrok-free.app -> http://localhost:8080
```
Keep this terminal/session running for as long as you want the webhook reachable.
💰 The free ngrok tier is enough for this — no need for a paid plan for a learning project.

## 4. Configure the GitHub webhook
In your GitHub repo → **Settings → Webhooks → Add webhook**:
- **Payload URL:** `https://a1b2-34-56-78-90.ngrok-free.app/github-webhook/`
  (note the trailing slash — Jenkins requires it)
- **Content type:** `application/json`
- **Which events:** "Just the push event"

## 5. Configure the Jenkins job
In your Jenkins pipeline job → **Configure**:
- Under **Build Triggers**, check **"GitHub hook trigger for GITScm polling"**
- Under **Pipeline**, point to this repo's `jenkins/Jenkinsfile`

## 6. Test it
Push a commit. GitHub calls the ngrok URL → ngrok forwards to your local
Jenkins → the job triggers automatically. Check **Recent Deliveries** in the
GitHub webhook settings page if it doesn't fire — it shows the exact
response Jenkins returned.

## Notes
- The free ngrok URL changes every time you restart ngrok — update the
  GitHub webhook payload URL each time, or get a static domain on ngrok's
  paid tier if you want it to persist.
- This approach only works while your laptop/VM and the ngrok tunnel are
  both running — for a "real" production setup you'd run Jenkins on an
  EC2 instance with a fixed address instead (see the Terraform-provisioned
  alternative in the main README).
