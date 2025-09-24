#!/usr/bin/env bash
set -euo pipefail

# Load environment variables from .env file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
fi

SRC_BUCKET="${SRC_BUCKET:?Defina SRC_BUCKET no .env}"
AWS_REGION="${AWS_REGION:?Defina AWS_REGION no .env}"

if [ "$#" -lt 1 ]; then
  echo "Uso: $0 <arquivos.pdf...>"
  exit 1
fi

for f in "$@"; do
  key="uploads/$(basename "$f")"
  echo "Enviando $f -> s3://$SRC_BUCKET/$key"
  aws s3 cp "$f" "s3://$SRC_BUCKET/$key" --region "$AWS_REGION"
done

echo "Upload concluído."
