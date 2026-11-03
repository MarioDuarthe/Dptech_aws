variable "lambdas" {
  type = map(object({
    layers     = optional(list(string), [])
    secrets    = optional(list(string), [])
    s3_buckets = optional(list(string), [])

    # REST API Gateway
    api = optional(map(object({
      methods          = list(string)
      use_authorizer   = optional(bool, true)
      api_key_required = optional(bool, true)
    })))

    # WebSocket API Gateway
    websocket = optional(object({
      routes               = list(string)
      authorization_header = optional(string, "authorizationToken")
    }))
  }))
}


variable "layers" {
  type = map(object({
    path      = optional(string)
    s3_bucket = optional(string)
    s3_key    = optional(string)
  }))

  default = {}
}


variable "lambda_sqs_permissions" {
  type    = map(list(string))
  default = {}
}


variable "lambda_sqs_triggers" {
  type = map(object({
    lambda     = string
    queue      = string
    alias      = string
    batch_size = optional(number, 10)
  }))

  default = {}
}