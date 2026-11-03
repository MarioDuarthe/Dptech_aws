lambdas = {

  "authorizer" = {
    handler = "main.lambda_handler"
    timeout = 10
    memory  = 128
    layers  = ["requests-layer", "pyjwt-layer"]
    secrets = [
      "Grmlab-dynamodb/HML",
      "Grmlab-dynamodb/PROD"
    ]
  }

  "app-meta" = {
    handler = "main.lambda_handler"
    timeout = 20
    memory  = 256
    layers  = ["requests-layer", "psycopg2-layer"]
    secrets = [
      "Grmlab-grmlabappnotificacoes/HML",
      "Grmlab-grmlabappnotificacoes/PROD"
    ]

    api = {
      "/app-meta/1017306474321872" = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/1465959594639373" = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/1517959456098342" = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/1518419522865720" = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/1554891153000082" = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/1681164246202172" = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/1682082859595609" = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/1767041554653976" = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/1822445772527230" = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/2155739648512896" = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/2325974568171263" = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/885286077596652"  = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
      "/app-meta/922418640863940"  = { methods = ["POST", "GET"], use_authorizer = false, api_key_required = false }
    }
  }

  "assinatura" = {
    handler = "main.lambda_handler"
    timeout = 30
    memory  = 128
    layers  = []
    s3_buckets = [
      "brzd-imagens-ia"
    ]
  }

  "mensagem-ativa" = {
    handler = "main.lambda_handler"
    timeout = 15
    memory  = 128
    layers  = ["requests-layer"]
    secrets = [
      "Grmlab-grmlabappnotificacoes/HML",
      "Grmlab-grmlabappnotificacoes/PROD"
    ]

    api = {
      "/comunicacao/envio-mensagem-ativa-template-meta" = { methods = ["POST"], use_authorizer = true, api_key_required = true }
    }
  }

  "odonto" = {
    handler = "main.lambda_handler"
    timeout = 15
    memory  = 128
    layers  = ["requests-layer", "psycopg2-layer"]
    secrets = [
      "BRZD-Grmlab_Odonto/HML",
      "BRZD-Grmlab_Odonto/PROD"
    ]
  }

  "saude" = {
    handler = "main.lambda_handler"
    timeout = 15
    memory  = 128
    layers  = ["requests-layer", "psycopg2-layer"]
    secrets = [
      "BRZD-Grmlab/HML",
      "BRZD-Grmlab/PROD"
    ]
  }

  "vendas" = {
    handler = "main.lambda_handler"
    timeout = 15
    memory  = 128
    layers  = ["requests-layer", "psycopg2-layer"]
    secrets = [
      "BRZD-Grmlab_Vendas/HML",
      "BRZD-Grmlab_Vendas/PROD"
    ]

    api = {
      "/servicos/checkoutvendas-confirmapagamento" = {
        methods          = ["POST"]
        use_authorizer   = true
        api_key_required = true
      }
    }
  }

  "agentevendas-simplus-mensagens" = {
    handler = "main.lambda_handler"
    timeout = 20
    memory  = 128
    layers  = []
    secrets = [
      "BRZD-Grmlab_Vendas/HML",
      "BRZD-Grmlab_Vendas/PROD"
    ]
  }

  "saude-externo" = {
    handler = "main.lambda_handler"
    timeout = 30
    memory  = 128
    layers  = []
    secrets = [
      "Grmlab-grmlabappnotificacoes/HML",
      "Grmlab-grmlabappnotificacoes/PROD",
      "Grmlab-dynamodb/HML",
      "Grmlab-dynamodb/PROD"
    ]

    websocket = {
      routes = [
        "$connect",
        "$default",
        "$disconnect",
        "teste"
      ]

      authorization_header = "authorizationToken"
    }
  }
}


layers = {

  "psycopg2-layer" = {
    s3_bucket = "grmlab-lambdas-layers"
    s3_key    = "layers/python-psycopg2-3_12-layer.zip"
  }

  "requests-layer" = {
    s3_bucket = "grmlab-lambdas-layers"
    s3_key    = "layers/python-requests-3_12-layer.zip"
  }

  "pyjwt-layer" = {
    s3_bucket = "grmlab-lambdas-layers"
    s3_key    = "layers/python-pyjwt-3_12-layer.zip"
  }
}