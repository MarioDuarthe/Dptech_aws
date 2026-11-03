import json


def lambda_handler(event, context):
    q = event.get("queryStringParameters") or {}

    texto = 'teste de atualização do fonte via github'

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
                }, ensure_ascii=False))

    # Responda 200 sempre e rápido, senão a Meta reenvia o evento
    return {"statusCode": 200, "body": "ok"}