resource "aws_sqs_queue" "jobs_queue" {
  name                      = "${var.project_name}-jobs"
  visibility_timeout_seconds = 900  # alinhado com Lambda timeout
  message_retention_seconds  = 86400
}
