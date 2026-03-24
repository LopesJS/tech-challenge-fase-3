locals {
  name = "${var.project}-${var.environment}"
}

# ─────────────────────────────────────────────────────────────────────────────
# DATA SOURCE: LabRole existente do AWS Academy
# NUNCA criar ou modificar esta role via Terraform
# ─────────────────────────────────────────────────────────────────────────────
data "aws_iam_role" "lab_role" {
  name = var.lab_role_name
}

# ─── Networking ───────────────────────────────────────────────────────────────
module "networking" {
  source = "../../modules/networking"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = var.availability_zones
}

# ─── EKS (usa LabRole para cluster e node group) ──────────────────────────────
module "eks" {
  source = "../../modules/eks"

  project            = var.project
  environment        = var.environment
  cluster_version    = var.eks_cluster_version
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  node_instance_type = var.eks_node_instance_type
  node_desired       = var.eks_node_desired
  node_min           = var.eks_node_min
  node_max           = var.eks_node_max

  # LabRole usada tanto no control plane quanto nos nodes
  lab_role_arn = data.aws_iam_role.lab_role.arn
}

# ─── ECR ──────────────────────────────────────────────────────────────────────
module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment
  services    = ["auth", "flag", "targeting", "evaluation", "analytics"]
}

# ─── RDS (3x PostgreSQL) ──────────────────────────────────────────────────────
module "rds" {
  source = "../../modules/rds"

  project            = var.project
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  eks_sg_id          = module.eks.node_security_group_id
  instance_class     = var.rds_instance_class
  master_username    = var.rds_username

  databases = [
    { name = "auth",      db_name = "auth_db"      },
    { name = "core",      db_name = "togglemaster" },
    { name = "targeting", db_name = "targeting_db" },
  ]
}

# ─── ElastiCache Redis ────────────────────────────────────────────────────────
module "elasticache" {
  source = "../../modules/elasticache"

  project            = var.project
  environment        = var.environment
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  eks_sg_id          = module.eks.node_security_group_id
}

# ─── DynamoDB ─────────────────────────────────────────────────────────────────
module "dynamodb" {
  source = "../../modules/dynamodb"

  project     = var.project
  environment = var.environment
}

# ─── SQS ──────────────────────────────────────────────────────────────────────
module "sqs" {
  source = "../../modules/sqs"

  project     = var.project
  environment = var.environment
}

# ─── ArgoCD via Helm ──────────────────────────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.1.3"
  namespace        = "argocd"
  create_namespace = true

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }
  set {
    name  = "server.extraArgs[0]"
    value = "--insecure"
  }

  depends_on = [module.eks]
}

# ─── Namespace togglemaster ───────────────────────────────────────────────────
resource "kubernetes_namespace" "togglemaster" {
  metadata {
    name = "togglemaster"
  }
  depends_on = [module.eks]
}

# ─── K8s Secrets — credenciais injetadas pelo Terraform ──────────────────────
resource "kubernetes_secret" "rds_credentials" {
  for_each = { for db in module.rds.db_instances : db.name => db }

  metadata {
    name      = "rds-${each.key}-secret"
    namespace = kubernetes_namespace.togglemaster.metadata[0].name
  }

  data = {
    host     = each.value.endpoint
    port     = "5432"
    username = each.value.username   # ← vem do output do módulo RDS
    password = each.value.password
    dbname   = each.value.db_name
  }

  depends_on = [module.rds]
}

resource "kubernetes_secret" "redis_credentials" {
  metadata {
    name      = "redis-secret"
    namespace = kubernetes_namespace.togglemaster.metadata[0].name
  }

  data = {
    host = module.elasticache.redis_endpoint
    port = "6379"
  }

  depends_on = [module.elasticache]
}

resource "kubernetes_secret" "sqs_config" {
  metadata {
    name      = "sqs-secret"
    namespace = kubernetes_namespace.togglemaster.metadata[0].name
  }

  data = {
    queue_url = module.sqs.queue_url
    region    = var.aws_region
  }

  depends_on = [module.sqs]
}
