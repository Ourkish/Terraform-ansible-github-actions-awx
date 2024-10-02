variable instancetype {
  type        = string
  description = "set aws instance type"
  default     = "t3.large"
}

variable aws_common_tag {
  type        = map
  description = "Set aws tag"
  default = {
    Name = "ec2-ourkish"
  }
}