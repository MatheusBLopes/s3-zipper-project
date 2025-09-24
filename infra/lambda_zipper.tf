# Zipper Lambda (consome SQS)
resource "aws_cloudwatch_log_group" "zipper_lg" {
  name              = "/aws/lambda/${var.project_name}-zipper"
  retention_in_days = 1
}

resource "aws_lambda_function" "zipper" {
  function_name = "${var.project_name}-zipper"
  role          = aws_iam_role.lambda_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.11"
  filename      = "${path.module}/../build/lambda_zipper.zip"
  source_code_hash = filebase64sha256("${path.module}/../build/lambda_zipper.zip")
  timeout       = 900   # 15 min (limite do Lambda)
  memory_size   = 512
  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.jobs_table.name
      S3_PART_SIZE = "8388608" # 8MB
      S3_READ_CHUNK = "1048576" # 1MB
    }
  }
}

resource "aws_lambda_event_source_mapping" "sqs_to_zipper" {
  event_source_arn = aws_sqs_queue.jobs_queue.arn
  function_name    = aws_lambda_function.zipper.arn
  batch_size       = 1
}
