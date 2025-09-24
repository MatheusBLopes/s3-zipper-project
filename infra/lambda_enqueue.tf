# Enqueue Lambda (POST /zip-jobs)
resource "aws_cloudwatch_log_group" "enqueue_lg" {
  name              = "/aws/lambda/${var.project_name}-enqueue"
  retention_in_days = 1
}

resource "aws_lambda_function" "enqueue" {
  function_name = "${var.project_name}-enqueue"
  role          = aws_iam_role.lambda_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  filename      = "${path.module}/../build/lambda_enqueue.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/lambda_enqueue.zip")
  timeout       = 10
  memory_size   = 256
  environment {
    variables = {
      TABLE_NAME           = aws_dynamodb_table.jobs_table.name
      QUEUE_URL            = aws_sqs_queue.jobs_queue.url
      PRESIGN_TTL_SECONDS  = tostring(var.presign_ttl_seconds)
      DST_PREFIX           = var.dst_prefix
    }
  }
}

resource "aws_apigatewayv2_integration" "enqueue_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.enqueue.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_zip_jobs" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /zip-jobs"
  target    = "integrations/${aws_apigatewayv2_integration.enqueue_integration.id}"
}

resource "aws_lambda_permission" "api_invoke_enqueue" {
  statement_id  = "AllowAPIGwInvokeEnqueue"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.enqueue.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
