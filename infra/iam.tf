data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Role comum para Lambdas com logs
resource "aws_iam_role" "lambda_role" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "basic_exec" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Políticas específicas (DDB, SQS, S3)
data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid = "DynamoDBAccess"
    actions = ["dynamodb:PutItem","dynamodb:GetItem","dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.jobs_table.arn]
  }

  statement {
    sid = "SQSAccess"
    actions = ["sqs:SendMessage","sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.jobs_queue.arn]
  }

  statement {
    sid = "S3SrcRead"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.src.arn}/*"]
  }

  statement {
    sid = "S3DstWrite"
    actions = ["s3:PutObject","s3:AbortMultipartUpload","s3:ListBucketMultipartUploads","s3:ListMultipartUploadParts","s3:CreateMultipartUpload","s3:CompleteMultipartUpload","s3:GetObject"]
    resources = ["${aws_s3_bucket.dst.arn}/*"]
  }

  statement {
    sid = "S3DstList"
    actions = ["s3:ListBucket"]
    resources = [aws_s3_bucket.dst.arn]
  }
}

resource "aws_iam_policy" "lambda_inline" {
  name   = "${var.project_name}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "attach_inline" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_inline.arn
}
