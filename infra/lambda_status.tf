# Status Lambda (GET /zip-jobs/{id})
resource "aws_cloudwatch_log_group" "status_lg" {
  name              = "/aws/lambda/${var.project_name}-status"
  retention_in_days = 1
}

resource "aws_lambda_function" "status" {
  function_name = "${var.project_name}-status"
  role          = aws_iam_role.lambda_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  filename      = "${path.module}/../build/lambda_status.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/lambda_status.zip")
  timeout       = 5
  memory_size   = 256
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.jobs_table.name
    }
  }
}

resource "aws_apigatewayv2_integration" "status_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.status.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_zip_job" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /zip-jobs/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.status_integration.id}"
}

resource "aws_lambda_permission" "api_invoke_status" {
  statement_id  = "AllowAPIGwInvokeStatus"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.status.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
