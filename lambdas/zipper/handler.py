import os
import json
import boto3
import logging
from zipstream import ZipFile  # zipstream-ng
from botocore.config import Config
from datetime import datetime, timezone, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3", config=Config(max_pool_connections=50))
dynamodb = boto3.resource("dynamodb")

TABLE_NAME = os.environ["TABLE_NAME"]
table = dynamodb.Table(TABLE_NAME)

S3_PART_SIZE = int(os.environ.get("S3_PART_SIZE", str(8 * 1024 * 1024)))  # 8 MB
DEFAULT_CHUNK = int(os.environ.get("S3_READ_CHUNK", str(1024 * 1024)))    # 1 MB

def s3_stream_object(bucket, key, chunk_size=DEFAULT_CHUNK):
    obj = s3.get_object(Bucket=bucket, Key=key)
    body = obj["Body"]
    for chunk in body.iter_chunks(chunk_size=chunk_size):
        if chunk:
            yield chunk

def zip_members_generator(src_bucket, keys):
    z = ZipFile(mode="w", compression=0)  # PDFs geralmente já comprimidos
    for key in keys:
        arcname = os.path.basename(key)
        logger.info("Adicionando ao ZIP: %s", key)
        z.write_iter(arcname, s3_stream_object(src_bucket, key))
    for data in z:
        yield data

def multipart_upload_from_iter(target_bucket, target_key, data_iter, part_size=S3_PART_SIZE):
    mpu = s3.create_multipart_upload(Bucket=target_bucket, Key=target_key)
    upload_id = mpu["UploadId"]
    parts = []
    buf = bytearray()
    part_number = 1
    try:
        for chunk in data_iter:
            buf += chunk
            while len(buf) >= part_size:
                to_send = bytes(buf[:part_size])
                resp = s3.upload_part(
                    Bucket=target_bucket, Key=target_key,
                    PartNumber=part_number, UploadId=upload_id, Body=to_send
                )
                parts.append({"ETag": resp["ETag"], "PartNumber": part_number})
                del buf[:part_size]
                part_number += 1

        if buf:
            resp = s3.upload_part(
                Bucket=target_bucket, Key=target_key,
                PartNumber=part_number, UploadId=upload_id, Body=bytes(buf)
            )
            parts.append({"ETag": resp["ETag"], "PartNumber": part_number})

        s3.complete_multipart_upload(
            Bucket=target_bucket, Key=target_key,
            MultipartUpload={"Parts": parts}, UploadId=upload_id
        )
    except Exception as e:
        s3.abort_multipart_upload(Bucket=target_bucket, Key=target_key, UploadId=upload_id)
        raise

def generate_presigned_url(bucket, key, ttl_seconds=86400):
    return s3.generate_presigned_url(
        ClientMethod="get_object",
        Params={"Bucket": bucket, "Key": key},
        ExpiresIn=ttl_seconds
    )

def process_job(job_id):
    logger.info("Processando job %s", job_id)
    resp = table.get_item(Key={"jobId": job_id})
    item = resp.get("Item")
    if not item:
        logger.warning("Job %s não encontrado", job_id)
        return

    if item["status"] == "READY":
        logger.info("Job %s já está READY, nada a fazer", job_id)
        return

    src_bucket = item["sourceBucket"]
    keys = item["keys"]
    dst_bucket = item.get("targetBucket", src_bucket)
    dst_key = item["targetKey"]
    ttl = int(item.get("presignTtlSeconds", 86400))

    # Gera iterador streaming do zip
    zip_iter = zip_members_generator(src_bucket, keys)

    # Envia via multipart
    multipart_upload_from_iter(dst_bucket, dst_key, zip_iter)

    # Gera URL pré-assinada
    url = generate_presigned_url(dst_bucket, dst_key, ttl)

    # Atualiza status
    table.update_item(
        Key={"jobId": job_id},
        UpdateExpression="SET #s=:s, downloadUrl=:u",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "READY", ":u": url}
    )
    logger.info("Job %s concluído. ZIP em s3://%s/%s", job_id, dst_bucket, dst_key)

def lambda_handler(event, context):
    logger.info("Evento SQS: %s", json.dumps(event))
    records = event.get("Records", [])
    for r in records:
        try:
            body = json.loads(r["body"])
            job_id = body["jobId"]
            process_job(job_id)
        except Exception:
            logger.exception("Falha processando mensagem: %s", r.get("messageId"))
    return {"ok": True}
