# S3 ZIP Jobs - Serverless PDF Archiving Service

A serverless AWS-based service that creates ZIP archives from PDF files stored in S3 buckets using **streaming processing** to handle large files without memory overflow.

## 🏗️ Architecture

```mermaid
flowchart LR
    client[Client] -->|POST /zip-jobs<br/>(list of PDFs)| apigw[API Gateway HTTP]
    apigw --> enqueue[Lambda Enqueue<br/>(creates job + sends to SQS)]
    enqueue -->|JobId + status=PENDING| ddb[(DynamoDB<br/>Job Status)]
    enqueue -->|Job message| sqs[(SQS Queue)]
    sqs --> zipper[Lambda Zipper<br/>(streaming ZIP -> S3)]
    zipper -->|Streaming read| s3src[(S3 Source PDFs)]
    zipper -->|Multipart Upload| s3dst[(S3 Generated ZIP)]
    zipper -->|status=READY<br/>+ outputKey + downloadUrl| ddb
    client <-->|GET /zip-jobs/{id}| apigw
    apigw <--> ddb
    apigw -->|downloadUrl if READY| client
```

### 🔄 Processing Flow

1. **Job Creation**: `POST /zip-jobs` receives a list of S3 object keys and creates a job in DynamoDB with `status=PENDING`, then publishes a message to SQS
2. **Streaming Processing**: The **Zipper Lambda** (SQS subscriber) reads each PDF from S3 **in streaming mode**, generates a ZIP using **zipstream-ng**, and uploads to S3 via **Multipart Upload**
3. **Completion**: Updates DynamoDB with `status=READY` and stores the `downloadUrl` (presigned URL)
4. **Status Check**: `GET /zip-jobs/{id}` returns the status and `downloadUrl` when available

### 🚀 Memory Optimization

- **Streaming S3 reads** (`iter_chunks`) and **streaming S3 writes** using **Multipart Upload**
- No `/tmp` or large `BytesIO` usage; fixed buffer size (8MB)
- Handles large file collections without memory overflow

## 📋 Requirements

- Terraform >= 1.5
- AWS CLI configured with appropriate permissions
- Python 3.11+ (for Lambda package dependencies)
- AWS account with sufficient permissions

## ⚙️ Configuration

### Main Terraform Variables

See `infra/variables.tf`. Key variables:

- `project_name` - Resource prefix (default: "s3-zip-jobs")
- `aws_region` - AWS region (default: "us-east-1")
- `src_bucket_name` - Source bucket for PDFs (required)
- `dst_bucket_name` - Destination bucket for ZIP files (required)
- `dst_prefix` - Destination prefix (default: "zips/")
- `presign_ttl_seconds` - Presigned URL TTL (default: 86400 = 24h)

### Environment Setup

1. Copy the environment template:
   ```bash
   cp scripts/env.example .env
   ```

2. Edit `.env` with your configuration:
   ```bash
   # S3 bucket names (must be globally unique)
   SRC_BUCKET=your-source-bucket-name
   DST_BUCKET=your-destination-bucket-name
   DST_PREFIX=zips/
   
   # API Gateway URL (filled after terraform apply)
   API_BASE=https://your-api-gateway-url.execute-api.us-east-1.amazonaws.com
   ```

## 🚀 Quick Start

```bash
# 1. Configure environment variables
cp scripts/env.example .env
# Edit .env with your bucket names

# 2. Build Lambda packages
make build

# 3. Deploy infrastructure (creates AWS resources)
make tf-init
make tf-apply

# 4. Upload test PDFs
scripts/upload_pdfs.sh examples/*.pdf

# 5. Test complete workflow
scripts/test_flow.sh
```

## 📡 API Endpoints

### Base URL
```
https://your-api-gateway-url.execute-api.us-east-1.amazonaws.com
```

### 1. Create ZIP Job
**POST** `/zip-jobs`

Creates a new ZIP job and returns a job ID for tracking.

**Request Body:**
```json
{
  "sourceBucket": "your-source-bucket",
  "targetBucket": "your-destination-bucket",
  "targetPrefix": "zips/",
  "keys": ["uploads/file1.pdf", "uploads/file2.pdf"]
}
```

**Response:**
```json
{
  "jobId": "12345678-1234-1234-1234-123456789abc",
  "status": "PENDING"
}
```

**cURL Example:**
```bash
curl -X POST https://your-api.execute-api.us-east-1.amazonaws.com/zip-jobs \
  -H "Content-Type: application/json" \
  -d '{
    "sourceBucket": "your-source-bucket",
    "targetBucket": "your-destination-bucket", 
    "targetPrefix": "zips/",
    "keys": ["uploads/test.pdf"]
  }'
```

### 2. Check Job Status
**GET** `/zip-jobs/{jobId}`

Returns the current status of a ZIP job.

**Response (PENDING):**
```json
{
  "jobId": "12345678-1234-1234-1234-123456789abc",
  "status": "PENDING"
}
```

**Response (READY):**
```json
{
  "jobId": "12345678-1234-1234-1234-123456789abc",
  "status": "READY",
  "downloadUrl": "https://s3.amazonaws.com/bucket/zips/file.zip?AWSAccessKeyId=...",
  "targetBucket": "your-destination-bucket",
  "targetKey": "zips/12345678-1234-1234-1234-123456789abc.zip"
}
```

**cURL Example:**
```bash
curl -X GET https://your-api.execute-api.us-east-1.amazonaws.com/zip-jobs/12345678-1234-1234-1234-123456789abc
```

**Download the ZIP:**
```bash
curl -O "https://s3.amazonaws.com/bucket/zips/file.zip?AWSAccessKeyId=..."
```

## 📁 Project Structure

- `infra/` - Terraform infrastructure for API Gateway HTTP, 3 Lambdas (enqueue/status/zipper), SQS, DynamoDB, S3, IAM, and CloudWatch (1-day retention)
- `lambdas/` - Lambda function code with CloudWatch logging
- `scripts/` - Helper scripts for PDF upload and end-to-end testing
- `Makefile` - Build/Deploy/Destroy and utility commands

## 🛠️ Available Scripts

### PDF Generation and Upload

```bash
# Generate 500 sample PDF files
scripts/generate_pdfs.sh 500

# Upload files to S3 with optimized settings
scripts/bulk_upload.sh --parallel 20 --batch 50 examples

# Generate and upload in one command
scripts/bulk_upload.sh --generate 500 --parallel 20 --batch 50
```

### Bulk Upload Options

- `--prefix PREFIX` - S3 prefix (default: `uploads/`)
- `--parallel NUM` - Number of parallel uploads (default: 10)
- `--batch NUM` - Batch size for processing (default: 50)
- `--generate NUM` - Generate NUM sample PDF files

### ZIP Creation and Testing

```bash
# Create ZIP with all PDFs from uploads/ prefix
scripts/test_flow.sh

# Create ZIP from specific prefix
scripts/test_flow.sh documents/

# Create ZIP from entire bucket
scripts/test_flow.sh ""

# Get help
scripts/test_flow.sh --help
```

## 💰 Cost Optimization

All services are configured with **minimal/on-demand** settings:
- DynamoDB on-demand pricing
- Standard SQS pricing
- Lambda with modest memory allocation
- Simple S3 buckets
- CloudWatch logs with **1-day retention**

## 🧹 Cleanup

```bash
# Remove all AWS resources (⚠️ destroys data in buckets)
make tf-destroy
```

## 📊 Complete Usage Example

```bash
# 1. Upload PDFs to S3 (using AWS CLI)
aws s3 cp document.pdf s3://your-source-bucket/uploads/

# 2. Create ZIP job
JOB_RESPONSE=$(curl -s -X POST https://your-api.execute-api.us-east-1.amazonaws.com/zip-jobs \
  -H "Content-Type: application/json" \
  -d '{
    "sourceBucket": "your-source-bucket",
    "targetBucket": "your-destination-bucket",
    "targetPrefix": "zips/",
    "keys": ["uploads/document.pdf"]
  }')

# 3. Extract job ID
JOB_ID=$(echo $JOB_RESPONSE | jq -r .jobId)
echo "Job created: $JOB_ID"

# 4. Wait for completion (polling)
while true; do
  STATUS_RESPONSE=$(curl -s https://your-api.execute-api.us-east-1.amazonaws.com/zip-jobs/$JOB_ID)
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
    echo "Error: $STATUS_RESPONSE"
    break
  fi
done
```

## 🔧 Makefile Commands

```bash
# Build Lambda packages
make build

# Deploy infrastructure
make tf-init
make tf-apply

# Test workflow
make test-flow

# Generate sample PDFs
make generate-pdfs COUNT=500

# Bulk upload files
make bulk-upload ARGS="--generate 500"

# Clean up
make tf-destroy
```

## 🎯 Use Cases

- **Document Archiving**: Bundle multiple PDFs into organized archives
- **Batch Processing**: Handle large collections of documents efficiently
- **API Integration**: Integrate with existing systems via REST API
- **Cost-Effective Storage**: Compress and organize files for long-term storage
- **On-Demand Packaging**: Create ZIP files only when needed

## 🔍 Monitoring and Debugging

- **CloudWatch Logs**: All Lambda functions log to CloudWatch with 1-day retention
- **DynamoDB**: Job status tracking and metadata storage
- **SQS**: Reliable message queuing for job processing
- **S3**: Source files and generated ZIP archives

## 📝 License

This project is open source and available under the MIT License.