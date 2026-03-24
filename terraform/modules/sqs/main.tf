variable "project"     { type = string }
variable "environment" { type = string }

resource "aws_sqs_queue" "analytics_dlq" {
  name                      = "${var.project}-${var.environment}-analytics-dlq"
  message_retention_seconds = 1209600 # 14 dias
}

resource "aws_sqs_queue" "analytics" {
  name                       = "${var.project}-${var.environment}-analytics"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.analytics_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "${var.project}-${var.environment}-analytics-queue" }
}

output "queue_url" { value = aws_sqs_queue.analytics.url }
output "queue_arn" { value = aws_sqs_queue.analytics.arn }
