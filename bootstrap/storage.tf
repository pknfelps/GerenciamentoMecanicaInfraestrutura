resource "aws_s3_bucket" "shared" {
  for_each      = local.buckets
  bucket        = each.value
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "shared" {
  for_each                = local.buckets
  bucket                  = aws_s3_bucket.shared[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "shared" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.shared[each.key].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "shared" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.shared[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "shared" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.shared[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "shared" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.shared[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [local.bucket_arns[each.key], "${local.bucket_arns[each.key]}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }], each.key == "artifacts" ? [{
      Sid       = "RequireConditionalArtifactCreation"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:PutObject"
      Resource  = "${local.bucket_arns.artifacts}/*"
      Condition = {
        Null = { "s3:if-none-match" = "true" }
        Bool = { "s3:ObjectCreationOperation" = "true" }
      }
    }] : [])
  })
  depends_on = [aws_s3_bucket_public_access_block.shared]
}

resource "aws_ecr_repository" "api" {
  name                 = local.ecr_name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  encryption_configuration {
    encryption_type = "AES256"
  }
  image_scanning_configuration {
    scan_on_push = true
  }
  lifecycle {
    prevent_destroy = true
  }
}