variable "project"     { type = string }
variable "environment" { type = string }

resource "aws_dynamodb_table" "analytics" {
  name         = "ToggleMasterAnalytics"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = { Name = "ToggleMasterAnalytics" }
}

output "table_name" { value = aws_dynamodb_table.analytics.name }
output "table_arn"  { value = aws_dynamodb_table.analytics.arn }
