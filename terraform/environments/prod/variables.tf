variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "togglemaster"
}

variable "environment" {
  type    = string
  default = "prod"
}

# ─── Networking ───────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.1.0/24", "10.10.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.10.10.0/24", "10.10.11.0/24"]
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

# ─── EKS ──────────────────────────────────────────────────────────────────────
variable "eks_cluster_version" {
  type    = string
  default = "1.29"
}

variable "eks_node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "eks_node_desired" {
  type    = number
  default = 2
}

variable "eks_node_min" {
  type    = number
  default = 1
}

variable "eks_node_max" {
  type    = number
  default = 4
}

# ─── RDS ──────────────────────────────────────────────────────────────────────
variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "rds_username" {
  type      = string
  default   = "postgres"
  sensitive = true
}

# ─── AWS Academy ──────────────────────────────────────────────────────────────
# Nome da role do laboratório — visível em:
# AWS Console → IAM → Roles → pesquisar "LabRole"
variable "lab_role_name" {
  description = "Nome exato da IAM Role do AWS Academy (geralmente 'LabRole')"
  type        = string
  default     = "LabRole"
}

# GitHub — usado apenas para gerar o secret de acesso ao ECR no workflow
variable "github_org" {
  description = "GitHub org/usuário (usado na documentação)"
  type        = string
  default     = ""
}

variable "github_repo" {
  description = "Nome do repositório GitHub"
  type        = string
  default     = "toggle-master-fase3"
}
