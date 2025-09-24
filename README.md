# S3 ZIP Jobs (Cenário A) — Infra mínima e streaming sem estourar memória

Este projeto cria uma API para receber uma lista de PDFs em um bucket S3, gerar um ZIP **em streaming** (sem carregar tudo em memória) e disponibilizar uma **URL pré‑assinada** para download.

## Arquitetura (Mermaid)

```mermaid
flowchart LR
    client[Cliente] -->|POST /zip-jobs<br/>(lista de PDFs)| apigw[API Gateway HTTP]
    apigw --> enqueue[Lambda Enqueue<br/>(cria job + envia p/ SQS)]
    enqueue -->|JobId + status=PENDING| ddb[(DynamoDB<br/>Job Status)]
    enqueue -->|Mensagem job| sqs[(SQS Queue)]
    sqs --> zipper[Lambda Zipper<br/>(streaming ZIP -> S3)]
    zipper -->|Leitura streaming| s3src[(S3 PDFs Origem)]
    zipper -->|Multipart Upload| s3dst[(S3 ZIP Gerado)]
    zipper -->|status=READY<br/>+ outputKey + downloadUrl| ddb
    client <-->|GET /zip-jobs/{id}| apigw
    apigw <--> ddb
    apigw -->|downloadUrl se READY| client
```

### Fluxo
1. `POST /zip-jobs` recebe `keys` (S3 object keys) e cria um **job** no DynamoDB com `status=PENDING`, depois publica a mensagem na **SQS**.
2. A **Lambda Zipper** (assinante da SQS) lê cada PDF do S3 **em streaming**, gera o ZIP com **zipstream-ng** e envia para o S3 via **Multipart Upload**.
3. Ao finalizar, atualiza o DynamoDB com `status=READY` e grava `downloadUrl` (pré‑assinada).
4. `GET /zip-jobs/{id}` retorna o status e a `downloadUrl` quando disponível.

### Como evita estouro de memória?
- Leitura **streaming** do S3 (`iter_chunks`) e escrita **streaming** para outro objeto no S3 com **Multipart Upload**.
- Não usa `/tmp` nem `BytesIO` gigantes; o buffer é fixo (ex.: 8 MB).

## Requisitos
- Terraform >= 1.5
- AWS CLI configurado
- Python 3.11+ (para empacotar dependências das Lambdas)
- Permissões na conta AWS

## Variáveis principais (Terraform)
Veja `infra/variables.tf`. Principais:
- `project_name` (prefixo dos recursos)
- `aws_region`
- `src_bucket_name` (bucket de origem dos PDFs)
- `dst_bucket_name` (bucket onde o ZIP será gravado, pode ser o mesmo do `src`)
- `dst_prefix` (ex.: `zips/`)
- `presign_ttl_seconds` (padrão 86400 = 24h)

## API Endpoints

### Base URL
```
https://s64dnr9vrk.execute-api.us-east-1.amazonaws.com
```

### 1. Create ZIP Job
**POST** `/zip-jobs`

Creates a new ZIP job and returns a job ID for tracking.

**Request Body:**
```json
{
  "sourceBucket": "s3-zip-jobs-source-2024",
  "targetBucket": "s3-zip-jobs-destination-2024", 
  "targetPrefix": "zips/",
  "keys": [
    "uploads/document1.pdf",
    "uploads/document2.pdf"
  ]
}
```

**cURL Example:**
```bash
curl -X POST https://s64dnr9vrk.execute-api.us-east-1.amazonaws.com/zip-jobs \
  -H "Content-Type: application/json" \
  -d '{
    "sourceBucket": "s3-zip-jobs-source-2024",
    "targetBucket": "s3-zip-jobs-destination-2024",
    "targetPrefix": "zips/",
    "keys": ["uploads/test.pdf"]
  }'
```

**Response (202 Created):**
```json
{
  "jobId": "1b0364c0-13cf-47d5-b9f7-67a7d8708eaf",
  "status": "PENDING"
}
```

### 2. Check Job Status
**GET** `/zip-jobs/{jobId}`

Retrieves the current status of a ZIP job.

**cURL Example:**
```bash
curl -X GET https://s64dnr9vrk.execute-api.us-east-1.amazonaws.com/zip-jobs/1b0364c0-13cf-47d5-b9f7-67a7d8708eaf
```

**Response - Job Pending (200 OK):**
```json
{
  "jobId": "1b0364c0-13cf-47d5-b9f7-67a7d8708eaf",
  "status": "PENDING"
}
```

**Response - Job Ready (200 OK):**
```json
{
  "jobId": "1b0364c0-13cf-47d5-b9f7-67a7d8708eaf",
  "status": "READY",
  "downloadUrl": "https://s3-zip-jobs-destination-2024.s3.amazonaws.com/zips/1b0364c0-13cf-47d5-b9f7-67a7d8708eaf.zip?AWSAccessKeyId=...",
  "targetBucket": "s3-zip-jobs-destination-2024",
  "targetKey": "zips/1b0364c0-13cf-47d5-b9f7-67a7d8708eaf.zip"
}
```

**Response - Job Not Found (404 Not Found):**
```json
{
  "error": "job não encontrado"
}
```

### 3. Download ZIP File
Once a job status is `READY`, use the `downloadUrl` from the status response to download the ZIP file.

**cURL Example:**
```bash
curl -O "https://s3-zip-jobs-destination-2024.s3.amazonaws.com/zips/1b0364c0-13cf-47d5-b9f7-67a7d8708eaf.zip?AWSAccessKeyId=..."
```

## Uso rápido

```bash
# 1) Configure variáveis
cp scripts/env.example .env
# Edite .env (nomes dos buckets etc.)

# 2) Build dos pacotes das Lambdas
make build

# 3) Provisionar infra (cuidado: cria recursos na sua conta)
make tf-init
make tf-apply

# 4) Subir alguns PDFs para teste (ajuste SRC_BUCKET no .env)
scripts/upload_pdfs.sh examples/*.pdf

# 5) Testar fluxo completo
scripts/test_flow.sh
```

## Exemplo de uso completo via cURL

```bash
# 1. Upload de PDFs para S3 (usando AWS CLI)
aws s3 cp document.pdf s3://s3-zip-jobs-source-2024/uploads/

# 2. Criar job de ZIP
JOB_RESPONSE=$(curl -s -X POST https://s64dnr9vrk.execute-api.us-east-1.amazonaws.com/zip-jobs \
  -H "Content-Type: application/json" \
  -d '{
    "sourceBucket": "s3-zip-jobs-source-2024",
    "targetBucket": "s3-zip-jobs-destination-2024",
    "targetPrefix": "zips/",
    "keys": ["uploads/document.pdf"]
  }')

# 3. Extrair jobId
JOB_ID=$(echo $JOB_RESPONSE | jq -r .jobId)
echo "Job criado: $JOB_ID"

# 4. Aguardar conclusão (polling)
while true; do
  STATUS_RESPONSE=$(curl -s https://s64dnr9vrk.execute-api.us-east-1.amazonaws.com/zip-jobs/$JOB_ID)
  STATUS=$(echo $STATUS_RESPONSE | jq -r .status)
  echo "Status: $STATUS"
  
  if [ "$STATUS" = "READY" ]; then
    DOWNLOAD_URL=$(echo $STATUS_RESPONSE | jq -r .downloadUrl)
    echo "Download URL: $DOWNLOAD_URL"
    curl -O "$DOWNLOAD_URL"
    break
  elif [ "$STATUS" = "PENDING" ]; then
    sleep 5
  else
    echo "Erro: $STATUS_RESPONSE"
    break
  fi
done
```

## Estrutura

- `infra/` — Terraform para API Gateway HTTP, 3 Lambdas (enqueue/status/zipper), SQS, DynamoDB, S3, IAM e CloudWatch (retention 1 dia).
- `lambdas/` — Código das Lambdas com logs no CloudWatch.
- `scripts/` — Auxiliares para upload de PDFs e teste fim‑a‑fim.
- `Makefile` — Build/Deploy/Destroy e utilitários.

## Custos
Todos os serviços estão na configuração **mínima**/sob demanda: DynamoDB on-demand, SQS padrão, Lambda com memória modesta, buckets simples, retenção de logs de **1 dia**.

> **Limpeza:** `make tf-destroy` remove todos os recursos (atenção a dados nos buckets).
