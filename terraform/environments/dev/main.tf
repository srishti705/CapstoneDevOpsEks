locals {
  name = "${var.project_name}-${var.environment}"
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

module "vpc" {
  source = "../../modules/vpc"

  name               = local.name
  single_nat_gateway = true # 💰 keep this true unless you need multi-AZ HA
  tags               = local.tags
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name            = "${local.name}-app"
  expire_untagged_after_days = 3
  tags                       = local.tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name        = "${local.name}-eks"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  node_instance_types = ["t3.medium"]
  capacity_type       = "SPOT" # 💰 switch to ON_DEMAND only if Spot capacity is unavailable
  desired_size        = 1
  min_size            = 1
  max_size            = 2
  tags                = local.tags
}
