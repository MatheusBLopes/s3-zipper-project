#!/usr/bin/env bash
set -euo pipefail

# Simple PDF generator for testing
# Creates minimal valid PDF files with content

COUNT=${1:-500}
OUTPUT_DIR="examples"

usage() {
    echo "Uso: $0 [NÚMERO]"
    echo ""
    echo "Gera arquivos PDF de exemplo para teste"
    echo "NÚMERO: quantidade de PDFs a gerar (padrão: 500)"
    echo ""
    echo "Exemplos:"
    echo "  $0 100    # Gera 100 PDFs"
    echo "  $0 500    # Gera 500 PDFs (padrão)"
    echo "  $0 1000   # Gera 1000 PDFs"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

echo "📄 Gerando $COUNT arquivos PDF de exemplo em $OUTPUT_DIR/"
mkdir -p "$OUTPUT_DIR"

for i in $(seq 1 $COUNT); do
    filename="document_$(printf "%04d" $i).pdf"
    filepath="$OUTPUT_DIR/$filename"
    
    # Create a simple but valid PDF
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
/Length 100
>>
stream
BT
/F1 12 Tf
72 720 Td
(Document $i) Tj
0 -20 Td
(Generated for S3 Zipper Test) Tj
0 -20 Td
(Timestamp: $(date)) Tj
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
500
%%EOF
EOF
    
    # Show progress every 50 files
    if [ $((i % 50)) -eq 0 ]; then
        echo "   ✅ Gerados $i/$COUNT arquivos..."
    fi
done

echo "🎉 Concluído! Gerados $COUNT arquivos PDF em $OUTPUT_DIR/"
echo ""
echo "Para fazer upload de todos os arquivos:"
echo "  ./scripts/bulk_upload.sh $OUTPUT_DIR"
echo ""
echo "Para fazer upload com configurações específicas:"
echo "  ./scripts/bulk_upload.sh --parallel 20 --batch 100 $OUTPUT_DIR"
