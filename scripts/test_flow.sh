#!/usr/bin/env bash
set -euo pipefail
: "${API_BASE:?Preencha API_BASE no .env}"
: "${AWS_REGION:?}"
: "${SRC_BUCKET:?}"
: "${DST_BUCKET:?}"
: "${DST_PREFIX:?}"

# Coletar algumas chaves do SRC_BUCKET (exemplo: uploads/*.pdf)
echo "Listando PDFs no s3://$SRC_BUCKET/uploads/"
mapfile -t KEYS < <(aws s3api list-objects-v2 --bucket "$SRC_BUCKET" --prefix "uploads/" --query "Contents[?ends_with(Key, `.pdf`)].Key" --output text --region "$AWS_REGION" | tr '\t' '\n')

if [ "${#KEYS[@]}" -eq 0 ]; then
  echo "Nenhum PDF encontrado em uploads/. Envie arquivos com scripts/upload_pdfs.sh"
  exit 1
fi

# Monta payload JSON
printf -v KEYS_JSON '%s","' "${KEYS[@]}"
KEYS_JSON='["'${KEYS_JSON%","}'"]'
PAYLOAD=$(jq -n --arg src "$SRC_BUCKET" --arg dst "$DST_BUCKET" --arg prefix "$DST_PREFIX" --argjson keys "$KEYS_JSON" '
  {sourceBucket:$src, targetBucket:$dst, targetPrefix:$prefix, keys:$keys}
' 2>/dev/null || true)

if [ -z "$PAYLOAD" ]; then
  # Fallback sem jq
  KEYS_COMMA=$(IFS=, ; echo "${KEYS[*]}")
  PAYLOAD="{\"sourceBucket\":\"$SRC_BUCKET\",\"targetBucket\":\"$DST_BUCKET\",\"targetPrefix\":\"$DST_PREFIX\",\"keys\":[\"${KEYS_COMMA//,/\",\"}\"]}"
fi

echo "Criando job..."
RESP=$(curl -s -X POST "$API_BASE/zip-jobs" -H 'Content-Type: application/json' -d "$PAYLOAD")
echo "Resposta: $RESP"
JOB_ID=$(echo "$RESP" | jq -r .jobId 2>/dev/null || echo "")
if [ -z "$JOB_ID" ] || [ "$JOB_ID" == "null" ]; then
  echo "Falha ao obter jobId"
  exit 1
fi

echo "Aguardando conclusão do job $JOB_ID ..."
for i in {1..120}; do
  STATUS_JSON=$(curl -s "$API_BASE/zip-jobs/$JOB_ID")
  STATUS=$(echo "$STATUS_JSON" | jq -r .status 2>/dev/null || echo "")
  echo "Tentativa $i: $STATUS"
  if [ "$STATUS" == "READY" ]; then
    URL=$(echo "$STATUS_JSON" | jq -r .downloadUrl 2>/dev/null || echo "")
    echo "Pronto! URL: $URL"
    exit 0
  fi
  sleep 5
done

echo "Timeout aguardando o job."
exit 1
