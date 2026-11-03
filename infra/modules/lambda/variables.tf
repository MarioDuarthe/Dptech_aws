variable "name" {}
variable "handler" {}
variable "timeout" { default = 10 }
variable "memory" { default = 128 }

variable "role_arn" {}

variable "layers" {
  type = list(string)
  default = []
}

variable "aliases" {
  type = list(string)
}

variable "environment_variables" {
  type = map(string)
  default = {}
}

variable "wait_iam_dependency" {
  type = any
}