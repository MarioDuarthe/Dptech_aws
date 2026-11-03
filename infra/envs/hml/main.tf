terraform {
  backend "s3" {
    bucket       = "grmlab-terraform-state"
    key          = "terraform/hml/terraform.tfstate"
    region       = "sa-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "sa-east-1"
}

/*resource "aws_iam_role" "lambda_role" {
  name = "grmlab-lambda-role-hml"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "time_sleep" "wait_iam" {
  depends_on = [aws_iam_role.lambda_role]

  create_duration = "10s"
}

resource "aws_iam_role_policy" "lambda_sqs_access" {
  for_each = var.lambda_sqs_permissions

  name = "grmlab-${each.key}-sqs-access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:DeleteMessageBatch",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [
          "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:fila-grmlab-*"
        ]
      }
    ]
  })
}*/

resource "aws_iam_role" "lambda" {
  for_each = var.lambdas

  name = "grmlab-${each.key}-role-hml"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  for_each = var.lambdas

  role       = aws_iam_role.lambda[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "time_sleep" "wait_iam" {
  depends_on = [
    aws_iam_role.lambda,
    aws_iam_role_policy_attachment.basic_execution
  ]

  create_duration = "10s"
}

resource "aws_iam_role_policy" "s3_access" {
  for_each = var.lambdas

  name = "grmlab-terraform-lambda-s3"
  role = aws_iam_role.lambda[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:CopyObject"
        ]
        Resource = [
          "arn:aws:s3:::grmlab-lambdas-log",
          "arn:aws:s3:::grmlab-lambdas-log/*",
          "arn:aws:s3:::grmlab-lambdas-layers",
          "arn:aws:s3:::grmlab-lambdas-layers/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_s3_access" {
  for_each = {
    for k, v in var.lambdas :
    k => v if length(v.s3_buckets) > 0
  }

  name = "s3-access"
  role = aws_iam_role.lambda[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = [
          for bucket in each.value.s3_buckets :
          "arn:aws:s3:::${bucket}"
        ]
      },
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]

        Resource = flatten([
          for bucket in each.value.s3_buckets : [
            "arn:aws:s3:::${bucket}/*"
          ]
        ])
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_secrets_access" {
  for_each = {
    for k, v in var.lambdas :
    k => v if length(v.secrets) > 0
  }

  name = "secrets-access"
  role = aws_iam_role.lambda[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]

        Resource = [
          for secret in each.value.secrets :
          "arn:aws:secretsmanager:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:secret:${secret}*"
        ]
      }
    ]
  })
}

# ========================
# ATRIBUIR LAYER NO LAMBDA
# ========================

resource "aws_lambda_layer_version" "layers" {
  for_each            = var.layers
  layer_name          = "grmlab-${each.key}"
  compatible_runtimes = ["python3.12"]

  # S3 (quando existir)
  s3_bucket = try(each.value.s3_bucket, null)
  s3_key    = try(each.value.s3_key, null)

  # Local (quando existir)
  filename         = try(each.value.path, null)
  source_code_hash = try(filebase64sha256(each.value.path), null)
}

# ========================
# MULTI-LAMBDA
# ========================
module "lambdas" {
  for_each = var.lambdas

  source = "../../modules/lambda"

  name                = each.key
  handler             = each.value.handler
  timeout             = each.value.timeout
  memory              = each.value.memory
  wait_iam_dependency = time_sleep.wait_iam

  role_arn = aws_iam_role.lambda[each.key].arn

  aliases = ["HML"]

  layers = [
    for l in each.value.layers :
    aws_lambda_layer_version.layers[l].arn
  ]

  environment_variables = {
    ENVIRONMENT = "HML"
    SECRET_NAME = "grmlab-${each.key}/HML"
  }
}

# ========================
# SECRET MANAGER
# ========================

/*
module "secrets" {
  for_each = {
    for k, v in var.lambdas :
    k => v if v.has_secret
  }

  source = "../../modules/secrets"

  name        = each.key
  environment = "HML"

  secret_file = "${path.module}/../../../secrets/hml/${each.key}.json"
} */

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

/*
resource "aws_iam_role_policy" "secrets_access" {
  name = "grmlab-secrets-access"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = flatten([
          for k, v in var.lambdas : [
            "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:grmlab-${k}/HML*",
            "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:grmlab-${k}/PROD*"
          ] if v.has_secret
        ])
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
      }
    ]
  })
} */


# ========================
# API GATEWAY
# ========================

module "api_gateway" {
  for_each = {
    for k, v in var.lambdas :
    k => v if try(v.api, null) != null
  }

  source = "../../modules/api-gateway"

  lambda_name = "grmlab-${each.key}"
  lambda_arn  = module.lambdas[each.key].arn

  region = "sa-east-1"

  environment  = "HML"
  lambda_alias = "HML"

  routes = each.value.api

  authorizer_lambda_name = "grmlab-authorizer"
  authorizer_lambda_arn  = module.lambdas["authorizer"].arn

  depends_on = [
    module.lambdas
  ]
}

# ============================================================
# API GATEWAY WEBSOCKET
# ============================================================

module "api_gateway_websocket" {
  for_each = {
    for k, v in var.lambdas :
    k => v if try(v.websocket, null) != null
  }

  source = "../../modules/api-websocket"

  name = "grmlab-${each.key}-websocket"

  region      = "sa-east-1"
  environment = "hml"

  lambda_name  = module.lambdas[each.key].function_name
  lambda_arn   = module.lambdas[each.key].arn
  lambda_alias = "HML"

  routes = each.value.websocket.routes

  authorization_header = each.value.websocket.authorization_header

  authorizer_lambda_name = module.lambdas["authorizer"].function_name
  authorizer_lambda_arn  = module.lambdas["authorizer"].arn

  depends_on = [
    module.lambdas
  ]
}

# ============================================================
# SSM - ID DAS WEBSOCKET APIs
#
# Salva o ID da WebSocket criada pelo HML para que o ambiente
# PROD possa reutilizar a mesma API.
# ============================================================

resource "aws_ssm_parameter" "websocket_api_id" {
  for_each = module.api_gateway_websocket

  name = "/grmlab/websocket/${each.key}/api-id"
  type = "String"

  value = each.value.api_id
}

# ========================
# SQS + DLQ
# ========================
/*
resource "aws_sqs_queue" "dlq" {
  for_each = var.sqs

  name = each.value.fifo ? "${replace(each.key, ".fifo", "")}-dlq.fifo" : "${each.key}-dlq"

  fifo_queue = each.value.fifo
}

resource "aws_sqs_queue" "queues" {
  for_each = var.sqs

  name = each.value.fifo ? (endswith(each.key, ".fifo") ? each.key : "${each.key}.fifo") : each.key

  fifo_queue                  = each.value.fifo
  content_based_deduplication = each.value.fifo ? true : null

  visibility_timeout_seconds = each.value.visibility_timeout

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = each.value.max_receive_count
  })
}

# ========================
# ATRIBUIR TRIGGER NO LAMBDA
# ========================

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  for_each = var.lambda_sqs_triggers

  event_source_arn = aws_sqs_queue.queues[each.value.queue].arn

  function_name = "${module.lambdas[each.value.lambda].function_name}:${each.value.alias}"

  batch_size = each.value.batch_size

  depends_on = [
    aws_sqs_queue.queues,
    module.lambdas
  ]
} */