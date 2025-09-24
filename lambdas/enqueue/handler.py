import json
import os
import uuid
import logging
import boto3
from datetime import datetime, timedelta, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
sqs = boto3.client("sqs")

TABLE_NAME = os.environ["TABLE_NAME"]
QUEUE_URL = os.environ["QUEUE_URL"]
PRESIGN_TTL_SECONDS = int(os.environ.get("PRESIGN_TTL_SECONDS", "86400"))
DST_PREFIX = os.environ.get("DST_PREFIX", "zips/")

table = dynamodb.Table(TABLE_NAME)

def lambda_handler(event, context):
    logger.info("Evento recebido: %s", json.dumps(event))
    try:
        body = json.loads(event.get("body") or "{}")
        keys = body.get("keys") or []
        source_bucket = body.get("sourceBucket")
        target_bucket = body.get("targetBucket") or source_bucket
        target_prefix = body.get("targetPrefix") or DST_PREFIX

        if not source_bucket or not keys:
            return _resp(400, {"error": "Informe sourceBucket e keys[]."})

        job_id = str(uuid.uuid4())
        target_key = f"{target_prefix}{job_id}.zip"

        expires_at = int((datetime.now(timezone.utc) + timedelta(seconds=PRESIGN_TTL_SECONDS)).timestamp())

        item = {
            "jobId": job_id,
            "status": "PENDING",
            "sourceBucket": source_bucket,
            "targetBucket": target_bucket,
            "targetKey": target_key,
            "keys": keys,
            "createdAt": int(datetime.now(timezone.utc).timestamp()),
            "presignTtlSeconds": PRESIGN_TTL_SECONDS,
            "expiresAt": expires_at,
        }
        logger.info("Gravando item no DynamoDB: %s", json.dumps(item))
        table.put_item(Item=item)

        msg = {"jobId": job_id}
        logger.info("Enviando mensagem para SQS: %s", json.dumps(msg))
        sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(msg))

        return _resp(202, {"jobId": job_id, "status": "PENDING"})
    except Exception as e:
        logger.exception("Falha no enqueue")
        return _resp(500, {"error": str(e)})

def _resp(code, body):
    return {
        "statusCode": code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
