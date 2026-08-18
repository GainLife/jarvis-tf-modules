output "id" {
  description = "Bucket id (the bucket name). Use this for resources declared outside the module, e.g. aws_s3_bucket_notification."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "bucket" {
  description = "Bucket name."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_domain_name" {
  description = "Global domain name, e.g. <name>.s3.amazonaws.com."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name. This is the one CloudFront origins should use."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "hosted_zone_id" {
  description = "Route53 hosted zone id for this bucket's region, for alias records."
  value       = aws_s3_bucket.this.hosted_zone_id
}
