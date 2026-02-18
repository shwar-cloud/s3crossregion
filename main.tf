terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Providers
#Source Region
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}
#Destination Region
provider "aws" {
  alias  = "oregon"
  region = "us-west-2"
}

## KMS Keys
data "aws_kms_key" "source_kms" {
  provider = aws.virginia
  key_id   = "2cc6fc85-4f8a-40e6-955d-afee4030f903"
}

data "aws_kms_key" "destination_kms" {
  provider = aws.oregon
  key_id   = "679a15c9-e045-4a7a-959d-084f7646a244"
}

## SNS Topic for Alerts
resource "aws_sns_topic" "replication_alerts" {
  provider = aws.virginia
  name     = "sclr-replication-alerts"
}

resource "aws_sns_topic_policy" "replication_alerts_policy" {
  provider = aws.virginia
  arn      = aws_sns_topic.replication_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "AllowS3ReplicationPublish"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.replication_alerts.arn
        Condition = {
          ArnLike = { "aws:SourceArn" = "arn:aws:s3:::source-sclrbucket1" }
        }
      },
      {
        Sid       = "AllowCloudWatchPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.replication_alerts.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "replication_email" {
  provider  = aws.virginia
  topic_arn = aws_sns_topic.replication_alerts.arn
  protocol  = "email"
  endpoint  = "changedev25@gmail.com"
}

## IAM Role for Replication
resource "aws_iam_role" "replication_role" {
  name = "sclr-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "s3.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "replication_policy" {
  role = aws_iam_role.replication_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration","s3:ListBucket"]
        Resource = "arn:aws:s3:::source-sclrbucket1"
      },
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectRetention",
          "s3:GetObjectLegalHold"
        ]
        Resource = "arn:aws:s3:::source-sclrbucket1/*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:ReplicateObjectRetention",
          "s3:ReplicateObjectLegalHold"
        ]
        Resource = "arn:aws:s3:::destination-sclrbucket2/*"
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Decrypt","kms:DescribeKey"]
        Resource = data.aws_kms_key.source_kms.arn
      },
      {
        Effect   = "Allow"
        Action   = ["kms:Encrypt","kms:ReEncrypt*","kms:GenerateDataKey*","kms:DescribeKey"]
        Resource = data.aws_kms_key.destination_kms.arn
      }
    ]
  })
}

## Source Bucket (Virginia)
resource "aws_s3_bucket" "source_bucket" {
  provider            = aws.virginia
  bucket              = "source-sclrbucket1"
  object_lock_enabled = true
}

resource "aws_s3_bucket_versioning" "source_versioning" {
  provider = aws.virginia
  bucket   = aws_s3_bucket.source_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "source_object_lock" {
  provider = aws.virginia
  bucket   = aws_s3_bucket.source_bucket.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 7
    }
  }
}
# Defalt Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "source_kms_encryption" {
  provider = aws.virginia
  bucket   = aws_s3_bucket.source_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = data.aws_kms_key.source_kms.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

# Source Bucket Policy to Enforce KMS Encryption
resource "aws_s3_bucket_policy" "source_enforce_kms" {
  provider = aws.virginia
  bucket   = aws_s3_bucket.source_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "DenyUnEncryptedUploads",
        Effect = "Deny",
        Principal = "*",
        Action = "s3:PutObject",   # Only applies to object upload
        Resource = "${aws_s3_bucket.source_bucket.arn}/*",
        #If the object upload does not specify server-side encryption with AWS KMS, deny it
        Condition = {
          StringNotEquals = {
            "s3:x-amz-server-side-encryption" = "aws:kms"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "source_public_block" {
  provider = aws.virginia
  bucket   = aws_s3_bucket.source_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "source_lifecycle" {
  provider = aws.virginia
  bucket   = aws_s3_bucket.source_bucket.id

  rule {
    id     = "source-lifecycle"
    status = "Enabled"
    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

## Destination Bucket (Oregon)
resource "aws_s3_bucket" "destination_bucket" {
  provider            = aws.oregon
  bucket              = "destination-sclrbucket2"
  object_lock_enabled = true
}

resource "aws_s3_bucket_versioning" "destination_versioning" {
  provider = aws.oregon
  bucket   = aws_s3_bucket.destination_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "destination_object_lock" {
  provider = aws.oregon
  bucket   = aws_s3_bucket.destination_bucket.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 7
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "destination_kms_encryption" {
  provider = aws.oregon
  bucket   = aws_s3_bucket.destination_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = data.aws_kms_key.destination_kms.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "destination_public_block" {
  provider = aws.oregon
  bucket   = aws_s3_bucket.destination_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

## Replication Configuration
resource "aws_s3_bucket_replication_configuration" "source_to_destination_replication" {
  provider = aws.virginia
  bucket   = aws_s3_bucket.source_bucket.id
  role     = aws_iam_role.replication_role.arn

  depends_on = [
    aws_s3_bucket_versioning.source_versioning,
    aws_s3_bucket_versioning.destination_versioning
  ]

  rule {
    id     = "replication-rule"
    status = "Enabled"
    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.destination_bucket.arn
      storage_class = "STANDARD"

      encryption_configuration {
        replica_kms_key_id = data.aws_kms_key.destination_kms.arn
      }

      replication_time {
        status = "Enabled"
        time { minutes = 15 }
      }

      metrics {
        status = "Enabled"
        event_threshold { minutes = 15 }
      }
    }

    source_selection_criteria {
      sse_kms_encrypted_objects { status = "Enabled" }
    }
  }
}

## Replication Failure Notification
resource "aws_s3_bucket_notification" "replication_failure" {
  provider = aws.virginia
  bucket   = aws_s3_bucket.source_bucket.id

  depends_on = [
    aws_s3_bucket_replication_configuration.source_to_destination_replication,
    aws_sns_topic_subscription.replication_email
  ]

  topic {
    topic_arn = aws_sns_topic.replication_alerts.arn
    events    = ["s3:Replication:OperationFailedReplication"]
  }
}

## CloudWatch Alarm
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider            = aws.virginia
  alarm_name          = "sclr-replication-lag"
  namespace           = "AWS/S3"
  metric_name         = "ReplicationTime"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 900 
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.replication_alerts.arn]

  dimensions = {
    BucketName  = aws_s3_bucket.source_bucket.bucket
    StorageType = "AllStorageTypes"
  }
}
