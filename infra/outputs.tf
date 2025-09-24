output "api_base_url" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

output "queue_url" {
  value = aws_sqs_queue.jobs_queue.url
}

output "table_name" {
  value = aws_dynamodb_table.jobs_table.name
}
