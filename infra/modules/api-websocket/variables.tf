variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "lambda_name" {
  type = string
}

variable "lambda_arn" {
  type = string
}

variable "lambda_alias" {
  type = string
}

variable "authorizer_lambda_name" {
  type = string
}

variable "authorizer_lambda_arn" {
  type = string
}

variable "routes" {
  type = list(string)
}

variable "authorization_header" {
  type    = string
  default = "authorizationToken"
}