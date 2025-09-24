import os
import json
import logging
import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["TABLE_NAME"]
table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    logger.info("Evento recebido: %s", json.dumps(event))
    job_id = event.get("pathParameters", {}).get("id")
    if not job_id:
        return _resp(400, {"error": "id do job não informado"})
    try:
        resp = table.get_item(Key={"jobId": job_id})
        item = resp.get("Item")
        if not item:
            return _resp(404, {"error": "job não encontrado"})

        body = {
            "jobId": item["jobId"],
            "status": item["status"],
        }
        if item["status"] == "READY":
            body["downloadUrl"] = item.get("downloadUrl")
            body["targetBucket"] = item.get("targetBucket")
            body["targetKey"] = item.get("targetKey")

        return _resp(200, body)
    except Exception as e:
        logger.exception("Erro consultando job")
        return _resp(500, {"error": str(e)})

def _resp(code, body):
    return {
        "statusCode": code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
