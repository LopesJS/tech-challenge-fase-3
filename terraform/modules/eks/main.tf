# ─────────────────────────────────────────────────────────────────────────────
# Módulo EKS — AWS Academy / LabRole
#
# RESTRIÇÕES DO ACADEMY:
#   - NÃO criar aws_iam_role para cluster ou nodes
#   - NÃO criar aws_iam_role_policy ou aws_iam_policy
#   - Usar a LabRole existente via variável lab_role_arn
#   - NÃO usar IRSA (IAM Roles for Service Accounts)
# ─────────────────────────────────────────────────────────────────────────────

variable "project"            { type = string }
variable "environment"        { type = string }
variable "cluster_version"    { type = string }
variable "vpc_id"             { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "node_instance_type" { type = string }
variable "node_desired"       { type = number }
variable "node_min"           { type = number }
variable "node_max"           { type = number }

# LabRole passada como variável — buscada via data source no root
variable "lab_role_arn" {
  description = "ARN da LabRole do AWS Academy — usada como cluster role E node role"
  type        = string
}

locals {
  cluster_name = "${var.project}-${var.environment}-cluster"
}

# ─── Security Group — Control Plane ──────────────────────────────────────────
resource "aws_security_group" "eks_cluster" {
  name        = "${local.cluster_name}-sg"
  description = "EKS cluster control plane security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.cluster_name}-sg" }
}

# ─── Security Group — Nodes ───────────────────────────────────────────────────
resource "aws_security_group" "eks_nodes" {
  name        = "${local.cluster_name}-nodes-sg"
  description = "EKS worker nodes security group"
  vpc_id      = var.vpc_id

  ingress {
    description = "Nodes se comunicam entre si"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description     = "Control plane → nodes"
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.cluster_name}-nodes-sg" }
}

# ─── EKS Cluster ──────────────────────────────────────────────────────────────
# role_arn = LabRole (não criamos, apenas referenciamos)
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = var.lab_role_arn   # ← LabRole

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }
}

# ─── EKS Node Group ───────────────────────────────────────────────────────────
# node_role_arn = LabRole (mesma role — Academy não permite criar roles separadas)
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-ng"
  node_role_arn   = var.lab_role_arn   # ← LabRole
  subnet_ids      = var.private_subnet_ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired
    min_size     = var.node_min
    max_size     = var.node_max
  }

  update_config {
    max_unavailable = 1
  }

  # Sem depends_on de policy attachments — LabRole já tem as policies necessárias
}

# ─── Outputs ──────────────────────────────────────────────────────────────────
output "cluster_name"              { value = aws_eks_cluster.main.name }
output "cluster_endpoint"          { value = aws_eks_cluster.main.endpoint }
output "cluster_ca_certificate"    { value = aws_eks_cluster.main.certificate_authority[0].data }
output "node_security_group_id"    { value = aws_security_group.eks_nodes.id }
output "cluster_security_group_id" { value = aws_security_group.eks_cluster.id }
