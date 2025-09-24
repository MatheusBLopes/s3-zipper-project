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

## Estrutura

- `infra/` — Terraform para API Gateway HTTP, 3 Lambdas (enqueue/status/zipper), SQS, DynamoDB, S3, IAM e CloudWatch (retention 1 dia).
- `lambdas/` — Código das Lambdas com logs no CloudWatch.
- `scripts/` — Auxiliares para upload de PDFs e teste fim‑a‑fim.
- `Makefile` — Build/Deploy/Destroy e utilitários.

## Custos
Todos os serviços estão na configuração **mínima**/sob demanda: DynamoDB on-demand, SQS padrão, Lambda com memória modesta, buckets simples, retenção de logs de **1 dia**.

> **Limpeza:** `make tf-destroy` remove todos os recursos (atenção a dados nos buckets).
