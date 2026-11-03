resource "aws_secretsmanager_secret" "this" {
  name = "grmlab-${var.name}/${var.environment}"

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id

  secret_string = jsonencode({
    Configuration = jsonencode(jsondecode(file(var.secret_file)))
  })
}