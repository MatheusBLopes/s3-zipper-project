resource "aws_s3_bucket" "src" {
  bucket = var.src_bucket_name
}

resource "aws_s3_bucket" "dst" {
  bucket = var.dst_bucket_name
}

# Lifecycle simples para limpar zips após 3 dias (opcional, baixo custo)
resource "aws_s3_bucket_lifecycle_configuration" "dst_lc" {
  bucket = aws_s3_bucket.dst.id
  rule {
    id     = "expire-zips"
    status = "Enabled"
    filter {
      prefix = var.dst_prefix
    }
    expiration {
      days = 3
    }
  }
}
