variable "project"            { type = string }
variable "environment"        { type = string }
variable "vpc_id"             { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "eks_sg_id"          { type = string }
variable "instance_class"     { type = string }
variable "master_username"    { type = string }
variable "databases" {
  type = list(object({
    name    = string
    db_name = string
  }))
}

# ─── Senhas aleatórias por instância ─────────────────────────────────────────
resource "random_password" "rds" {
  for_each = { for db in var.databases : db.name => db }
  length   = 24
  special  = false
}

# ─── Subnet Group ─────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-${var.environment}-rds-subnet-group"
  subnet_ids = var.private_subnet_ids
}

# ─── Security Group ───────────────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${var.project}-${var.environment}-rds-sg"
  description = "Allow PostgreSQL from EKS nodes"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_sg_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-${var.environment}-rds-sg" }
}

# ─── RDS Instances ────────────────────────────────────────────────────────────
resource "aws_db_instance" "main" {
  for_each = { for db in var.databases : db.name => db }

  identifier        = "${var.project}-${var.environment}-${each.key}"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = each.value.db_name
  username = var.master_username
  password = random_password.rds[each.key].result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  skip_final_snapshot     = true
  backup_retention_period = 7
  deletion_protection     = false

  tags = { Name = "${var.project}-${var.environment}-rds-${each.key}" }
}

# ─── Outputs ──────────────────────────────────────────────────────────────────
output "db_instances" {
  sensitive = true
  value = [
    for name, db in aws_db_instance.main : {
      name     = name
      endpoint = db.address
      username = db.username          # ← incluso para uso direto no kubernetes_secret
      db_name  = db.db_name
      password = random_password.rds[name].result
    }
  ]
}
