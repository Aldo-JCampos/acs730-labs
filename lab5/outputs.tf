output "vpc_id" {
  description = "Id of the VPC this configuration created."
  value       = aws_vpc.main.id
}
output "subnet_ids" {
  description = "Public subnet ids, keyed like var.public_subnets."
  value       = { for key, subnet in aws_subnet.public : key => subnet.id }
}
output "web_public_ip" {
  description = "Public IP of the web server. LocalStack invents one; it does not route."
  value       = aws_instance.web.public_ip
}
output "web_url" {
  description = "URL to curl once the instance has booted. Real AWS only."
  value       = "http://${aws_instance.web.public_ip}/"
}
output "artifact_bucket" {
  description = "Name of the optional bucket, or null when it was not created."
  value       = one(aws_s3_bucket.artifacts[*].bucket)
}
output "provider_target" {
  description = "Which endpoint this run actually talked to."
  value       = local.provider_target
}
