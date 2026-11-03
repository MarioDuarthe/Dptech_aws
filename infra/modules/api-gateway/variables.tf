variable "lambda_name" {}
variable "lambda_arn" {}
variable "environment" {}
variable "lambda_alias" {}
variable "region" {}
variable "authorizer_lambda_name" {}
variable "authorizer_lambda_arn" {}

variable "routes" {
  type = map(object({
    methods          = list(string)
    use_authorizer   = optional(bool, true)
    api_key_required = optional(bool, true)
  }))
}