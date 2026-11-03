# ============================================================
# WEBSOCKET API
# ============================================================

resource "aws_apigatewayv2_api" "this" {
  name                       = var.name
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}


# ============================================================
# INTEGRATION
#
# Todas as rotas serão enviadas para o mesmo Lambda.
# ============================================================

resource "aws_apigatewayv2_integration" "lambda" {
  api_id = aws_apigatewayv2_api.this.id

  integration_type   = "AWS_PROXY"
  integration_method = "POST"

  integration_uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${var.lambda_arn}:$${stageVariables.lambdaAlias}/invocations"
}


# ============================================================
# LAMBDA AUTHORIZER
#
# WebSocket utiliza REQUEST Authorizer.
# ============================================================

resource "aws_apigatewayv2_authorizer" "this" {
  api_id = aws_apigatewayv2_api.this.id

  name            = "grmlab-shared-authorizer"
  authorizer_type = "REQUEST"

  authorizer_uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${var.authorizer_lambda_arn}:$${stageVariables.lambdaAlias}/invocations"

  identity_sources = [
    "route.request.header.${var.authorization_header}"
  ]
}


# ============================================================
# $connect
#
# Única rota onde o WebSocket permite Lambda Authorizer.
# ============================================================

resource "aws_apigatewayv2_route" "connect" {
  api_id = aws_apigatewayv2_api.this.id

  route_key = "$connect"

  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"

  authorization_type = "CUSTOM"
  authorizer_id       = aws_apigatewayv2_authorizer.this.id
}


# ============================================================
# DEMAIS ROTAS
#
# $default
# $disconnect
# ============================================================

resource "aws_apigatewayv2_route" "routes" {
  for_each = toset([
    for route in var.routes :
    route if route != "$connect"
  ])

  api_id = aws_apigatewayv2_api.this.id

  route_key = each.value

  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"

  authorization_type = "NONE"
}


# ============================================================
# STAGE
#
# Auto deploy evita precisar criar deployment manual.
# ============================================================

resource "aws_apigatewayv2_stage" "this" {
  api_id = aws_apigatewayv2_api.this.id

  name        = var.environment
  auto_deploy = true

  stage_variables = {
    lambdaAlias = var.lambda_alias
  }
}


# ============================================================
# PERMISSION
# ============================================================

resource "aws_lambda_permission" "websocket_lambda" {
  statement_id = "AllowWebSocketInvoke-${var.environment}"

  action = "lambda:InvokeFunction"

  function_name = var.lambda_name
  qualifier     = var.lambda_alias

  principal = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.this.execution_arn}/*"
}


# ============================================================
# PERMISSION
#
# API Gateway -> Authorizer
# ============================================================

resource "aws_lambda_permission" "websocket_authorizer" {
  statement_id = "AllowWebSocketAuthorizer-${var.environment}"

  action = "lambda:InvokeFunction"

  function_name = var.authorizer_lambda_name
  qualifier     = var.lambda_alias

  principal = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.this.execution_arn}/*"
}