locals {
  routes_parsed = {
    for route, config in var.routes :
    route => {
      parts            = compact(split("/", route))
      methods          = config.methods
      use_authorizer   = config.use_authorizer
      api_key_required = config.api_key_required
    }
  }

  base_paths = toset([
    for route, config in local.routes_parsed :
    config.parts[0]
  ])

  route_methods = {
    for item in flatten([
      for route, config in local.routes_parsed : [
        for method in config.methods : {
          key              = "${route}-${upper(method)}"
          route            = route
          base             = config.parts[0]
          endpoint         = config.parts[1]
          method           = upper(method)
          use_authorizer   = config.use_authorizer
          api_key_required = config.api_key_required
        }
      ]
    ]) : item.key => item
  }
}

resource "aws_api_gateway_rest_api" "this" {
  name = var.lambda_name
}

// criação dinamica dos paths
/* resource "aws_api_gateway_resource" "servicos" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "servicos"
} */

resource "aws_api_gateway_resource" "base_paths" {
  for_each = local.base_paths

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = each.value
}

resource "aws_api_gateway_resource" "endpoints" {
  for_each = local.routes_parsed

  rest_api_id = aws_api_gateway_rest_api.this.id

  parent_id = aws_api_gateway_resource.base_paths[
    each.value.parts[0]
  ].id

  path_part = each.value.parts[1]
}

//endpoint dinamico
/*resource "aws_api_gateway_resource" "endpoints" {
  for_each = var.routes

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.servicos.id
  path_part   = each.key
}*/

//metodo (api key required / authorization)
resource "aws_api_gateway_method" "method" {
  for_each = local.route_methods

  rest_api_id = aws_api_gateway_rest_api.this.id

  resource_id = aws_api_gateway_resource.endpoints[
    each.value.route
  ].id

  http_method = each.value.method

  authorization = each.value.use_authorizer ? "CUSTOM" : "NONE"

  authorizer_id = each.value.use_authorizer ? aws_api_gateway_authorizer.this.id : null

  api_key_required = each.value.api_key_required
}

//Integração com o alias do lambda dinamico
resource "aws_api_gateway_integration" "integration" {
  for_each = local.route_methods

  rest_api_id = aws_api_gateway_rest_api.this.id

  resource_id = aws_api_gateway_resource.endpoints[
    each.value.route
  ].id

  http_method = aws_api_gateway_method.method[
    each.key
  ].http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"

  uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${var.lambda_arn}:$${stageVariables.lambdaAlias}/invocations"
}

resource "random_id" "lambda_permission" {
  byte_length = 2
}

resource "aws_lambda_permission" "apigw" {
  statement_id = "Allow-${var.lambda_name}-${var.lambda_alias}-${random_id.lambda_permission.hex}"

  action        = "lambda:InvokeFunction"
  function_name = var.lambda_arn
  qualifier     = var.lambda_alias
  principal     = "apigateway.amazonaws.com"

  depends_on = [
    aws_api_gateway_rest_api.this
  ]

  source_arn = "${aws_api_gateway_rest_api.this.execution_arn}/*"
}


resource "aws_lambda_permission" "authorizer" {
  statement_id  = "AllowAuthorizer-${var.lambda_alias}-${random_id.auth.hex}"
  action        = "lambda:InvokeFunction"

  function_name = var.authorizer_lambda_name
  qualifier     = var.lambda_alias

  principal = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_integration.integration
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

//criação de stage
resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id

  stage_name = "${lower(var.environment)}-v1"

  variables = {
    lambdaAlias = var.lambda_alias
  }
}

// inclusão de authorizer
resource "aws_api_gateway_authorizer" "this" {
  name = "grmlab-shared-authorizer"
  rest_api_id = aws_api_gateway_rest_api.this.id

  authorizer_uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${var.authorizer_lambda_arn}:$${stageVariables.lambdaAlias}/invocations"

  type = "TOKEN"

  identity_source = "method.request.header.authorizationToken"

  authorizer_result_ttl_in_seconds = 300
}

//tempo limite para criação do lambda

resource "time_sleep" "wait_lambda" {
  depends_on = [var.lambda_arn]

  create_duration = "10s"
}

resource "random_id" "auth" {
  byte_length = 2
}