output "vpc_id" {
  value = module.networking.vpc_id
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repositories" {
  value = module.ecr.repository_urls
}

output "rds_endpoints" {
  value     = { for db in module.rds.db_instances : db.name => db.endpoint }
  sensitive = true
}

output "redis_endpoint" {
  value     = module.elasticache.redis_endpoint
  sensitive = true
}

output "sqs_queue_url" {
  value = module.sqs.queue_url
}

output "dynamodb_table_name" {
  value = module.dynamodb.table_name
}

output "lab_role_arn" {
  description = "ARN da LabRole sendo usada (confirmar que está correta)"
  value       = data.aws_iam_role.lab_role.arn
}

output "kubeconfig_command" {
  description = "Comando para configurar kubectl localmente"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "argocd_get_password" {
  description = "Comando para obter a senha inicial do ArgoCD"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
