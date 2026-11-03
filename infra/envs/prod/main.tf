terraform {
  backend "s3" {
    bucket       = "grmlab-terraform-state"
    key          = "terraform/prod/terraform.tfstate"
    region       = "sa-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "sa-east-1"
}


# ============================================================
# DATA SOURCES
# ============================================================

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}


# ============================================================
# LAMBDAS EXISTENTES
#
# As funções Lambda são criadas/gerenciadas pelo ambiente HML.
# PROD apenas reutiliza as mesmas funções e cria o alias PROD.
# ============================================================

data "aws_lambda_function" "existing" {
  for_each = var.lambdas

  function_name = "grmlab-${each.key}"
}


# ============================================================
# ALIAS PROD
# ============================================================

resource "aws_lambda_alias" "prod" {
  for_each = var.lambdas

  name = "PROD"

  function_name = data.aws_lambda_function.existing[
    each.key
  ].function_name

  function_version = data.aws_lambda_function.existing[
    each.key
  ].version

  lifecycle {
    ignore_changes = [
      function_version
    ]
  }
}


# ============================================================
# API GATEWAY REST EXISTENTE
#
# A API Gateway é criada/gerenciada pelo HML.
# PROD apenas localiza a API existente para criar seu stage.
# ============================================================

data "aws_api_gateway_rest_api" "existing" {
  for_each = {
    for k, v in var.lambdas :
    k => v if try(v.api, null) != null
  }

  name = "grmlab-${each.key}"
}


# ============================================================
# API GATEWAY REST DEPLOYMENT - PROD
# ============================================================

resource "aws_api_gateway_deployment" "prod" {
  for_each = data.aws_api_gateway_rest_api.existing

  rest_api_id = each.value.id

  lifecycle {
    create_before_destroy = true
  }
}


# ============================================================
# API GATEWAY REST STAGE - PROD
#
# hml-v1  -> lambdaAlias = HML
# prod-v1 -> lambdaAlias = PROD
# ============================================================

resource "aws_api_gateway_stage" "prod" {
  for_each = data.aws_api_gateway_rest_api.existing

  stage_name = "prod"

  rest_api_id = each.value.id

  deployment_id = aws_api_gateway_deployment.prod[
    each.key
  ].id

  variables = {
    lambdaAlias = "PROD"
  }
}


# ============================================================
# PERMISSÃO
# API GATEWAY REST -> LAMBDA : PROD
# ============================================================

resource "aws_lambda_permission" "apigw_lambda_prod" {
  for_each = data.aws_api_gateway_rest_api.existing

  statement_id = "AllowAPIGatewayInvoke-${each.key}-PROD"

  action = "lambda:InvokeFunction"

  function_name = data.aws_lambda_function.existing[
    each.key
  ].function_name

  qualifier = "PROD"

  principal = "apigateway.amazonaws.com"

  source_arn = "${each.value.execution_arn}/*/*"

  depends_on = [
    aws_lambda_alias.prod
  ]
}


# ============================================================
# PERMISSÃO
# API GATEWAY REST -> AUTHORIZER : PROD
# ============================================================

resource "aws_lambda_permission" "apigw_authorizer_prod" {
  for_each = data.aws_api_gateway_rest_api.existing

  statement_id = "AllowAPIGatewayInvokeAuthorizer-${each.key}-PROD"

  action = "lambda:InvokeFunction"

  function_name = data.aws_lambda_function.existing[
    "authorizer"
  ].function_name

  qualifier = "PROD"

  principal = "apigateway.amazonaws.com"

  source_arn = "${each.value.execution_arn}/*/*"

  depends_on = [
    aws_lambda_alias.prod
  ]
}


# ============================================================
# WEBSOCKET API EXISTENTE
#
# A WebSocket API é criada pelo HML.
# PROD recupera o ID salvo no SSM.
# ============================================================

data "aws_ssm_parameter" "websocket_api_id" {
  for_each = {
    for k, v in var.lambdas :
    k => v if try(v.websocket, null) != null
  }

  name = "/grmlab/websocket/${each.key}/api-id"
}


# ============================================================
# WEBSOCKET STAGE - PROD
#
# prod-v1 -> lambdaAlias = PROD
# ============================================================

resource "aws_apigatewayv2_stage" "websocket_prod" {
  for_each = data.aws_ssm_parameter.websocket_api_id

  api_id = each.value.value

  name        = "prod"
  auto_deploy = true

  stage_variables = {
    lambdaAlias = "PROD"
  }
}


# ============================================================
# PERMISSÃO
# WEBSOCKET -> LAMBDA : PROD
# ============================================================

resource "aws_lambda_permission" "websocket_lambda_prod" {
  for_each = data.aws_ssm_parameter.websocket_api_id

  statement_id = "AllowWebSocketInvoke-${each.key}-PROD"

  action = "lambda:InvokeFunction"

  function_name = data.aws_lambda_function.existing[
    each.key
  ].function_name

  qualifier = "PROD"

  principal = "apigateway.amazonaws.com"

  //source_arn = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${each.value.value}/*"
  source_arn = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${each.value.value}/*"

  depends_on = [
    aws_lambda_alias.prod
  ]
}


# ============================================================
# PERMISSÃO
# WEBSOCKET -> AUTHORIZER : PROD
# ============================================================

resource "aws_lambda_permission" "websocket_authorizer_prod" {
  for_each = data.aws_ssm_parameter.websocket_api_id

  statement_id = "AllowWebSocketAuthorizer-${each.key}-PROD"

  action = "lambda:InvokeFunction"

  function_name = data.aws_lambda_function.existing[
    "authorizer"
  ].function_name

  qualifier = "PROD"

  principal = "apigateway.amazonaws.com"

  //source_arn = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${each.value.value}/*"
  source_arn = "arn:aws:execute-api:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${each.value.value}/*"

  depends_on = [
    aws_lambda_alias.prod
  ]
}


# ============================================================
# SQS EXISTENTES
#
# As filas não serão recriadas pelo ambiente PROD.
# O Terraform apenas consulta as filas já existentes.
# ============================================================

/*data "aws_sqs_queue" "queues" {
  for_each = toset(
    flatten(
      values(var.lambda_sqs_permissions)
    )
  )

  name = each.value
}*/


# ============================================================
# SQS -> LAMBDA PROD
#
# Cria o Event Source Mapping apontando especificamente para
# o alias informado no terraform.tfvars (normalmente PROD).
# ============================================================

/*resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  for_each = var.lambda_sqs_triggers

  event_source_arn = data.aws_sqs_queue.queues[
    each.value.queue
  ].arn

  function_name = "${data.aws_lambda_function.existing[
    each.value.lambda
  ].function_name}:${each.value.alias}"

  batch_size = each.value.batch_size

  depends_on = [
    aws_lambda_alias.prod
  ]
}*/
