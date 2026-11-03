resource "aws_lambda_function" "this" {
  function_name = "grmlab-${var.name}"

  handler = var.handler
  runtime = "python3.12"

  role = var.role_arn

  filename         = "${path.module}/dummy.zip"
  source_code_hash = filebase64sha256("${path.module}/dummy.zip")

  timeout = var.timeout
  memory_size = var.memory

  layers = var.layers

  environment {
    variables = var.environment_variables
  }

  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash
    ]
  }
  depends_on = [
  var.wait_iam_dependency
  ]
}

/*resource "aws_lambda_version" "this" {
  function_name = aws_lambda_function.this.function_name
}*/

resource "aws_lambda_alias" "aliases" {
  for_each = toset(var.aliases)

  name             = each.key
  function_name    = aws_lambda_function.this.function_name
  function_version = "$LATEST"

  depends_on = [aws_lambda_function.this]
}