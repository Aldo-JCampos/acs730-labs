variable "environment" {
  description = "Which environment this copy of the module is for."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging or prod."
  }
}

variable "instance_count" {
  description = "How many web servers to run."
  type        = number
  default     = 1
  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 3
    error_message = "instance_count must be 1 to 3. The term budget is $50 in total."
  }
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_type)
    error_message = "Stay small: t3.micro or t3.small."
  }
}

variable "instance_profile" {
  description = "Instance profile the Academy account already provides. Lets Session Manager reach the instance."
  type        = string
  default     = "LabInstanceProfile"
}

variable "cpu_alarm_threshold" {
  description = "Average CPU percent above which the alarm fires."
  type        = number
  default     = 70
}
