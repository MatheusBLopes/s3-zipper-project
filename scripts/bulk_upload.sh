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

# Default values
UPLOAD_PREFIX="uploads/"
PARALLEL_UPLOADS=10
BATCH_SIZE=50
GENERATE_SAMPLE_FILES=false
SAMPLE_COUNT=500

usage() {
    echo "Uso: $0 [OPÇÕES] [DIRETÓRIO_OU_ARQUIVOS...]"
    echo ""
    echo "Opções:"
    echo "  -p, --prefix PREFIX    Prefixo no S3 (padrão: uploads/)"
    echo "  -n, --parallel NUM     Número de uploads paralelos (padrão: 10)"
    echo "  -b, --batch NUM        Tamanho do lote para processar (padrão: 50)"
    echo "  -g, --generate NUM     Gerar NUM arquivos PDF de exemplo"
    echo "  -h, --help            Mostrar esta ajuda"
    echo ""
    echo "Exemplos:"
    echo "  $0 /path/to/pdf/directory"
    echo "  $0 file1.pdf file2.pdf file3.pdf"
    echo "  $0 --generate 500"
    echo "  $0 --parallel 20 --batch 100 /path/to/pdfs"
}

generate_sample_pdfs() {
    local count=$1
    local output_dir="examples"
    
    echo "Gerando $count arquivos PDF de exemplo em $output_dir/"
    mkdir -p "$output_dir"
    
    for i in $(seq 1 $count); do
        local filename="sample_$(printf "%03d" $i).pdf"
        local filepath="$output_dir/$filename"
        
        # Create a simple PDF with some content
        cat > "$filepath" << EOF
%PDF-1.4
1 0 obj
<<
/Type /Catalog
/Pages 2 0 R
>>
endobj

2 0 obj
<<
/Type /Pages
/Kids [3 0 R]
/Count 1
>>
endobj

3 0 obj
<<
/Type /Page
/Parent 2 0 R
/MediaBox [0 0 612 792]
/Contents 4 0 R
/Resources <<
/Font <<
/F1 5 0 R
>>
>>
>>
endobj

4 0 obj
<<
/Length 44
>>
stream
BT
/F1 12 Tf
72 720 Td
(Sample PDF $i) Tj
ET
endstream
endobj

5 0 obj
<<
/Type /Font
/Subtype /Type1
/BaseFont /Helvetica
>>
endobj

xref
0 6
0000000000 65535 f 
0000000010 00000 n 
0000000053 00000 n 
0000000110 00000 n 
0000000251 00000 n 
0000000345 00000 n 
trailer
<<
/Size 6
/Root 1 0 R
>>
startxref
420
%%EOF
EOF
    done
    
    echo "✅ Gerados $count arquivos PDF em $output_dir/"
    echo "$output_dir"
}

upload_file() {
    local file_path="$1"
    local s3_key="$2"
    local retry_count=0
    local max_retries=3
    
    while [ $retry_count -lt $max_retries ]; do
        if aws s3 cp "$file_path" "s3://$SRC_BUCKET/$s3_key" --region "$AWS_REGION" --only-show-errors; then
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                echo "⚠️  Falha no upload de $file_path, tentativa $((retry_count + 1))/$max_retries"
                sleep 2
            fi
        fi
    done
    
    echo "❌ Falha definitiva no upload de $file_path após $max_retries tentativas"
    return 1
}

upload_batch() {
    local files=("$@")
    local batch_size=${#files[@]}
    local success_count=0
    local failed_files=()
    
    echo "📦 Processando lote de $batch_size arquivos..."
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            local filename=$(basename "$file")
            local s3_key="${UPLOAD_PREFIX}${filename}"
            
            echo "⬆️  Enviando: $filename"
            if upload_file "$file" "$s3_key"; then
                success_count=$((success_count + 1))
            else
                failed_files+=("$file")
            fi
        else
            echo "⚠️  Arquivo não encontrado: $file"
            failed_files+=("$file")
        fi
    done
    
    echo "📊 Lote concluído: $success_count/$batch_size sucessos"
    
    if [ ${#failed_files[@]} -gt 0 ]; then
        echo "❌ Arquivos com falha:"
        for failed_file in "${failed_files[@]}"; do
            echo "   - $failed_file"
        done
    fi
    
    return ${#failed_files[@]}
}

# Parse command line arguments
files_to_upload=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--prefix)
            UPLOAD_PREFIX="$2"
            shift 2
            ;;
        -n|--parallel)
            PARALLEL_UPLOADS="$2"
            shift 2
            ;;
        -b|--batch)
            BATCH_SIZE="$2"
            shift 2
            ;;
        -g|--generate)
            GENERATE_SAMPLE_FILES=true
            SAMPLE_COUNT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "❌ Opção desconhecida: $1"
            usage
            exit 1
            ;;
        *)
            files_to_upload+=("$1")
            shift
            ;;
    esac
done

# Generate sample files if requested
if [ "$GENERATE_SAMPLE_FILES" = true ]; then
    sample_dir=$(generate_sample_pdfs "$SAMPLE_COUNT")
    files_to_upload+=("$sample_dir")
fi

# Check if we have files to upload
if [ ${#files_to_upload[@]} -eq 0 ]; then
    echo "❌ Nenhum arquivo ou diretório especificado"
    usage
    exit 1
fi

# Collect all PDF files
all_pdfs=()
for item in "${files_to_upload[@]}"; do
    if [ -d "$item" ]; then
        echo "📁 Processando diretório: $item"
        while IFS= read -r -d '' file; do
            all_pdfs+=("$file")
        done < <(find "$item" -name "*.pdf" -type f -print0)
    elif [ -f "$item" ]; then
        if [[ "$item" == *.pdf ]]; then
            all_pdfs+=("$item")
        else
            echo "⚠️  Ignorando arquivo não-PDF: $item"
        fi
    else
        echo "⚠️  Arquivo/diretório não encontrado: $item"
    fi
done

total_files=${#all_pdfs[@]}

if [ $total_files -eq 0 ]; then
    echo "❌ Nenhum arquivo PDF encontrado"
    exit 1
fi

echo "🚀 Iniciando upload de $total_files arquivos PDF para s3://$SRC_BUCKET/$UPLOAD_PREFIX"
echo "📊 Configurações:"
echo "   - Bucket: $SRC_BUCKET"
echo "   - Região: $AWS_REGION"
echo "   - Prefixo: $UPLOAD_PREFIX"
echo "   - Tamanho do lote: $BATCH_SIZE"
echo "   - Uploads paralelos: $PARALLEL_UPLOADS"
echo ""

# Process files in batches
total_success=0
total_failed=0
batch_num=1

for ((i=0; i<total_files; i+=BATCH_SIZE)); do
    batch_files=("${all_pdfs[@]:$i:$BATCH_SIZE}")
    batch_size=${#batch_files[@]}
    
    echo "🔄 Processando lote $batch_num (arquivos $((i+1))-$((i+batch_size)) de $total_files)"
    
    if upload_batch "${batch_files[@]}"; then
        echo "✅ Lote $batch_num concluído com sucesso"
    else
        echo "⚠️  Lote $batch_num concluído com algumas falhas"
    fi
    
    total_success=$((total_success + batch_size))
    batch_num=$((batch_num + 1))
    
    # Small delay between batches to avoid overwhelming the API
    if [ $i -lt $((total_files - BATCH_SIZE)) ]; then
        sleep 1
    fi
done

echo ""
echo "🎉 Upload concluído!"
echo "📊 Estatísticas finais:"
echo "   - Total de arquivos: $total_files"
echo "   - Uploads bem-sucedidos: $total_success"
echo "   - Falhas: $((total_files - total_success))"

if [ $total_success -eq $total_files ]; then
    echo "✅ Todos os arquivos foram enviados com sucesso!"
    exit 0
else
    echo "⚠️  Alguns arquivos falharam no upload"
    exit 1
fi
