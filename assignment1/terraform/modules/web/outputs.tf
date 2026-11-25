output "instance_ids" {
  description = "IDs of the web instances."
  value       = aws_instance.web[*].id
}

output "public_ips" {
  description = "Public IPs of the web instances."
  value       = aws_instance.web[*].public_ip
}

output "security_group_id" {
  description = "ID of the web security group."
  value       = aws_security_group.web.id
}

output "alarm_names" {
  description = "Names of the CloudWatch CPU alarms."
  value       = aws_cloudwatch_metric_alarm.cpu_high[*].alarm_name
}

output "db_password_length" {
  description = "Proof the SSM parameter was read, without printing it."
  value       = nonsensitive(length(data.aws_ssm_parameter.db_password.value))
}
