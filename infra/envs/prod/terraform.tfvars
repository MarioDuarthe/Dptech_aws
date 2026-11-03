lambdas = {

  "authorizer" = {
    layers = ["requests-layer", "pyjwt-layer"]
  }

  "app-meta" = {
    layers = ["requests-layer", "psycopg2-layer"]
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
    layers = []
  }

  "mensagem-ativa" = {
    layers = ["requests-layer"]
    api = {
      "/comunicacao/envio-mensagem-ativa-template-meta" = { methods = ["POST"], use_authorizer = true, api_key_required = true }
    }
  }

  "odonto" = {
    layers = ["requests-layer", "psycopg2-layer"]
  }

  "saude" = {
    layers = ["requests-layer", "psycopg2-layer"]
  }

  "vendas" = {
    layers = ["requests-layer", "psycopg2-layer"]
    api = {
      "/servicos/checkoutvendas-confirmapagamento" = { methods = ["POST"], use_authorizer = true, api_key_required = true }
    }
  }

  "saude-externo" = {
    layers = []
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