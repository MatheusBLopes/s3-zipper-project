#!/usr/bin/env bash
set -euo pipefail

# Load environment variables from .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

: "${API_BASE:?Preencha API_BASE no .env}"
: "${AWS_REGION:?}"
: "${SRC_BUCKET:?}"
: "${DST_BUCKET:?}"
: "${DST_PREFIX:?}"

# Coletar algumas chaves do SRC_BUCKET (exemplo: uploads/*.pdf)
echo "Listando PDFs no s3://$SRC_BUCKET/uploads/"
mapfile -t KEYS < <(aws s3api list-objects-v2 --bucket "$SRC_BUCKET" --prefix "uploads/" --query "Contents[?ends_with(Key, \`.pdf\`)].Key" --output text --region "$AWS_REGION" | tr '\t' '\n')

if [ "${#KEYS[@]}" -eq 0 ]; then
  echo "Nenhum PDF encontrado em uploads/. Envie arquivos com scripts/upload_pdfs.sh"
  exit 1
fi

# Monta payload JSON sem jq
KEYS_COMMA=$(IFS=, ; echo "${KEYS[*]}")
PAYLOAD="{\"sourceBucket\":\"$SRC_BUCKET\",\"targetBucket\":\"$DST_BUCKET\",\"targetPrefix\":\"$DST_PREFIX\",\"keys\":[\"${KEYS_COMMA//,/\",\"}\"]}"

echo "Criando job..."
RESP=$(curl -s -X POST "$API_BASE/zip-jobs" -H 'Content-Type: application/json' -d "$PAYLOAD")
echo "Resposta: $RESP"
# Extract jobId without jq
JOB_ID=$(echo "$RESP" | sed -n 's/.*"jobId": *"\([^"]*\)".*/\1/p')
if [ -z "$JOB_ID" ]; then
  echo "Falha ao obter jobId da resposta: $RESP"
  exit 1
fi
echo "Job criado com ID: $JOB_ID"

echo "Aguardando conclusão do job $JOB_ID ..."
for i in {1..120}; do
  STATUS_JSON=$(curl -s "$API_BASE/zip-jobs/$JOB_ID")
  STATUS=$(echo "$STATUS_JSON" | sed -n 's/.*"status": *"\([^"]*\)".*/\1/p')
  echo "Tentativa $i: $STATUS"
  if [ "$STATUS" == "READY" ]; then
    URL=$(echo "$STATUS_JSON" | sed -n 's/.*"downloadUrl": *"\([^"]*\)".*/\1/p')
    echo "Pronto! URL: $URL"
    exit 0
  fi
  sleep 5
done

echo "Timeout aguardando o job."
exit 1
