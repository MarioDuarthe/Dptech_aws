import json
import time
import logging
import re
import boto3
import botocore.config
import base64
from typing import Dict, Any, Optional, Tuple
from botocore.exceptions import ClientError


logger = logging.getLogger()
logger.setLevel(logging.INFO)

# ===========================================================================
# CONFIGURAÇÕES
# ===========================================================================
REGION_NAME = "us-east-1"
SECRET_BASE = "app-meta-notificacoes"

# Timeout boto3 para o Secrets Manager
SM_BOTO3_CONFIG = botocore.config.Config(
    connect_timeout=3,
    read_timeout=3,
    retries={"max_attempts": 1}
)


# ===========================================================================
# SECRETS MANAGER
# ===========================================================================
def load_config_from_secret_manager(alias: str) -> dict:
    """
    Carrega configuração do AWS Secrets Manager.

    Nome do secret: proxy-whatsapp/{alias}
    Onde alias = HML ou PRD (extraído da URL)

    Estrutura do secret:
    {
      "DB_HOST": "...",
      "DB_PORT": "5432",
      "DB_NAME": "...",
      "DB_USER": "...",
      "DB_PASSWORD": "...",
      "DB_TABLE": "whatsapp_dispatch_log",
      "WEBHOOK_VERIFY_TOKEN": "...",
      "PRAMERETROS_META": [...],
      "WEBHOOKS": [...],
      "WEBHOOKS_EXTERNOS": [...]
    }
    """
    secret_name = f"{SECRET_BASE}/{alias}" if alias else SECRET_BASE

    logger.info(f"[Secret Manager] Tentando acessar: {secret_name}")
    logger.info(f"[Secret Manager] Region: {REGION_NAME}")

    try:
        client = boto3.client(
            "secretsmanager",
            region_name=REGION_NAME,
            config=SM_BOTO3_CONFIG
        )

        response = client.get_secret_value(SecretId=secret_name)

        if "SecretString" in response:
            config = json.loads(response["SecretString"])
            logger.info(f"[Secret Manager] ✅ ACESSO CONCEDIDO - Secret '{secret_name}' carregado com sucesso!")
            # logger.info(f"[Secret Manager] Conteúdo bruto: {json.dumps(config, ensure_ascii=False)[:500]}")

            # Se o secret tem um campo "Configuration" com string JSON, desempacota
            if "Configuration" in config and isinstance(config["Configuration"], str):
                logger.info(f"[Secret Manager] Detectado campo 'Configuration' com string JSON, desempacotando...")
                config = json.loads(config["Configuration"])
                logger.info(f"[Secret Manager] ✅ Configuration desempacotado com sucesso!")

            # logger.info(f"[Secret Manager] Conteúdo final: {json.dumps(config, ensure_ascii=False, indent=2)[:1000]}")

            # Log de validação dos campos principais
            has_db = bool(config.get("DB_HOST"))
            has_webhooks = bool(config.get("WEBHOOKS"))
            logger.info(
                f"[Secret Manager] Validação: DB_HOST={'✅' if has_db else '❌'}, WEBHOOKS={'✅' if has_webhooks else '❌'}")

            return config
        else:
            logger.error(f"[Secret Manager] ❌ ACESSO NEGADO - Secret não contém SecretString")
            raise ValueError("Secret não contém SecretString")

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        error_msg = str(e)

        logger.error(f"[Secret Manager] ❌ ACESSO NEGADO - Erro AWS: {error_code}")
        logger.error(f"[Secret Manager] Detalhes: {error_msg}")

        if error_code == "ResourceNotFoundException":
            logger.error(f"[Secret Manager] Secret '{secret_name}' NÃO EXISTE no AWS Secrets Manager")
        elif error_code == "AccessDeniedException":
            logger.error(f"[Secret Manager] Lambda NÃO TEM PERMISSÃO para acessar '{secret_name}'")

        raise Exception(f"Erro ao acessar Secret Manager: {error_code}")

    except Exception as e:
        logger.error(f"[Secret Manager] ❌ ERRO INESPERADO: {type(e).__name__}: {str(e)}")
        raise

def extract_alias_and_id_from_event(event: dict) -> tuple:
    """
    Extrai o alias (HML/PROD) e o ID do webhook a partir do evento do API Gateway.

    Exemplo (evento real):
    - stage = "hml", path = "/whatsApp/1320798471125982"
      → ("HML", "1320798471125982")
    """
    request_context = event.get("requestContext") or {}

    # Ambiente: vem do stage do API Gateway
    stage = (request_context.get("stage") or "").lower()
    if stage in ("prd", "prod"):
        alias = "PROD"
    elif stage == "hml":
        alias = "HML"
    else:
        alias = None

    # ID do webhook: vem do path (sem stage)
    path = event.get("path") or ""
    match = re.search(r"/whatsApp/(\d+)", path, re.IGNORECASE)
    webhook_id = match.group(1) if match else None

    if alias is None or webhook_id is None:
        return None, None

    return alias, webhook_id

# ===========================================================================
# UTILITÁRIOS
# ===========================================================================
def build_response(status_code: int, body: dict) -> dict:
    """Constrói resposta HTTP para API Gateway."""
    logger.info(f"[build_response] Retornando statusCode={status_code}")
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body, ensure_ascii=False)
    }

# ===========================================================================
# HANDLER PRINCIPAL
# ===========================================================================
def lambda_handler(event : dict, context: Any) -> dict:
    """
        Handler principal da Lambda.

        Fluxo:
        0. Verifica se é webhook verification da Meta (GET com hub.challenge)
        1. Recebe JSON da Meta
        2. Verifica se contém array 'messages'
        3. Se TEM messages: encaminha para webhook configurado
        4. Se NÃO TEM messages: grava status na tabela whatsapp_dispatch_log
        """
    start_time = time.time()

    # Obtem request_id do context (atributo correto: aws_request_id)
    try:
        request_id = context.aws_request_id if context else "local-test"
    except (AttributeError, TypeError):
        request_id = "local-test"

    try:
        # Log inicial
        http_method = event.get("httpMethod", "UNKNOWN")
        path = event.get("path", "") or event.get("resource", "UNKNOWN")
        logger.info(f"[{request_id}] {http_method} {path}")

        # Extrai alias (HML/PRD) e ID do webhook da URL
        alias, webhook_id = extract_alias_and_id_from_event(event)

        if not alias:
            logger.error(f"[{request_id}] Path inválido. Esperado: /hml/whatsApp/{{ID}} ou /prod/whatsApp/{{ID}}")
            return build_response(400, {"error": "Path inválido. Formato esperado: /hml-v1/whatsApp/{ID}"})

        if not webhook_id:
            logger.error(f"[{request_id}] ID do webhook não encontrado na URL")
            return build_response(400, {"error": "ID do webhook não encontrado"})

        logger.info(f"[{request_id}] Alias: {alias}, Webhook ID: {webhook_id}")

        # Carrega configuração do Secret Manager
        try:
            config = load_config_from_secret_manager(alias)
        except Exception as e:
            logger.error(f"[{request_id}] Erro ao carregar Secret Manager: {str(e)}")
            return build_response(502, {"error": "Erro ao acessar configurações", "detail": str(e)})

        print(json.dumps(event, ensure_ascii=False))

        return {"statusCode": 200, "body": "ok"}


    except Exception as e:
        # Captura qualquer erro inesperado
        logger.error(f"[{request_id}] ERRO FATAL: {type(e).__name__}: {str(e)}")
        import traceback
        logger.error(traceback.format_exc())

        return {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "error": "Internal server error",
                "message": str(e),
                "type": type(e).__name__,
                "request_id": request_id
            }, ensure_ascii=False)
        }






    '''print(json.dumps(event, ensure_ascii=False))

    q = event.get("queryStringParameters") or {}

    # Verificação da Meta (GET)
    if "hub.challenge" in q:
        return {"statusCode": 200,
                "headers": {"Content-Type": "text/plain"},
                "body": q["hub.challenge"]}

    # Corpo do POST (o API Gateway às vezes envia em base64)
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        raw = base64.b64decode(raw).decode("utf-8")
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return {"statusCode": 200, "body": "ok"}

    for entry in payload.get("entry", []):
        waba_id = entry.get("id")
        for change in entry.get("changes", []):
            if change.get("field") != "messages":
                continue
            value = change.get("value", {})
            phone_number_id = value.get("metadata", {}).get("phone_number_id")
            nomes = {c.get("wa_id"): c.get("profile", {}).get("name")
                     for c in value.get("contacts", [])}

            # Mensagens recebidas do cliente
            for msg in value.get("messages", []):
                tipo = msg.get("type")
                if tipo == "text":
                    conteudo = msg["text"]["body"]
                elif tipo == "button":
                    conteudo = msg["button"].get("text")
                elif tipo == "interactive":
                    inter = msg["interactive"]
                    resp = inter.get("button_reply") or inter.get("list_reply") or {}
                    conteudo = resp.get("title")
                elif tipo in ("image", "audio", "video", "document", "sticker"):
                    conteudo = f"[{tipo}] media_id={msg[tipo].get('id')}"
                else:
                    conteudo = f"[{tipo}]"

                print(json.dumps({
                    "evento": "mensagem",
                    "waba_id": waba_id,
                    "phone_number_id": phone_number_id,
                    "de": msg.get("from"),
                    "nome": nomes.get(msg.get("from")),
                    "message_id": msg.get("id"),
                    "tipo": tipo,
                    "conteudo": conteudo,
                    "timestamp": msg.get("timestamp"),
                }, ensure_ascii=False))
                # TODO: salvar no banco e/ou responder pela API

            # Status das mensagens que você enviou
            for st in value.get("statuses", []):
                print(json.dumps({
                    "evento": "status",
                    "message_id": st.get("id"),
                    "status": st.get("status"),  # sent, delivered, read, failed
                    "para": st.get("recipient_id"),
                    "erros": st.get("errors"),  # só aparece em failed
                    "timestamp": st.get("timestamp"),
                }, ensure_ascii=False))'''

    # Responda 200 sempre e rápido, senão a Meta reenvia o evento
    return {"statusCode": 200, "body": "ok"}