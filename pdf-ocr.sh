#!/usr/bin/env bash
# pdf-ocr.sh — Convert PDF/image files to text using the dots.ocr API
# Usage: ./pdf-ocr.sh <file> [--page N] [--output file.txt]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- helpers ----------

usage() {
    cat <<'EOF'
Usage: ./pdf-ocr.sh <file> [options]

Extract text from PDF or image files using the dots.ocr API.

Arguments:
  <file>              PDF or image file (PNG, JPG, JPEG, TIFF, BMP, WEBP)

Options:
  --page N            Process only page N of a PDF (default: all pages)
  --output FILE       Write output to FILE instead of stdout
  --help              Show this help message

Examples:
  ./pdf-ocr.sh document.pdf
  ./pdf-ocr.sh document.pdf --page 2
  ./pdf-ocr.sh document.pdf --output result.txt
  ./pdf-ocr.sh photo.png
  cat document.pdf | ./pdf-ocr.sh --output result.txt

The script reads VLLM_TOKEN and API_PORT from .env (same directory).
EOF
    exit 0
}

info()  { echo >&2 "[INFO]  $*"; }
warn()  { echo >&2 "[WARN]  $*"; }
error() { echo >&2 "[ERROR] $*"; exit 1; }

# ---------- dependency checks ----------

check_deps() {
    local missing=()
    for cmd in curl base64; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    # pdftoppm only required when processing PDFs
    if [[ "${NEED_PDFTOPPM:-0}" == "1" ]] && ! command -v pdftoppm >/dev/null 2>&1; then
        missing+=("pdftoppm (install poppler-utils)")
    fi
    if (( ${#missing[@]} )); then
        error "Missing dependencies: ${missing[*]}"
    fi
}

# ---------- read config from .env ----------

load_config() {
    API_TOKEN="${VLLM_TOKEN:-your-secret-token-here}"
    API_PORT="${API_PORT:-8000}"

    if [ -f "$SCRIPT_DIR/.env" ]; then
        local val
        val=$(grep -E '^VLLM_TOKEN=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2-) || true
        [ -n "$val" ] && API_TOKEN="$val"
        val=$(grep -E '^API_PORT=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2-) || true
        [ -n "$val" ] && API_PORT="$val"
    fi

    API_URL="http://localhost:${API_PORT}/v1/chat/completions"
}

# ---------- health check ----------

check_health() {
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        "http://localhost:${API_PORT}/health" 2>/dev/null) || true
    if [ "$status" != "200" ]; then
        error "dots.ocr service is not reachable on port ${API_PORT}. Start it with: ./dots-ocr-manager.sh up"
    fi
}

# ---------- OCR a single image ----------

ocr_image() {
    local image_file="$1"
    local mime_type="$2"

    local file_base64
    file_base64=$(base64 -w 0 "$image_file")

    # Write JSON payload to a temp file to avoid argument-list-too-long errors
    local payload_file
    payload_file=$(mktemp)
    cat > "$payload_file" <<JSONEOF
{
    "model": "dots-ocr",
    "messages": [
        {
            "role": "user",
            "content": [
                {
                    "type": "image_url",
                    "image_url": {
                        "url": "data:${mime_type};base64,${file_base64}"
                    }
                },
                {
                    "type": "text",
                    "text": "Extract all text from this document."
                }
            ]
        }
    ],
    "max_tokens": 2048
}
JSONEOF

    local response
    response=$(curl -s -w "\n%{http_code}" --max-time 120 \
        -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -d @"$payload_file")
    rm -f "$payload_file"

    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" != "200" ]; then
        warn "API returned HTTP $http_code"
        echo "$body" >&2
        return 1
    fi

    # Extract text from JSON response
    echo "$body" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['choices'][0]['message']['content'])" 2>/dev/null || echo "$body"
}

# ---------- detect mime type ----------

detect_mime() {
    local file="$1"
    local ext="${file##*.}"
    ext="${ext,,}"  # lowercase
    case "$ext" in
        png)             echo "image/png" ;;
        jpg|jpeg)        echo "image/jpeg" ;;
        tiff|tif)        echo "image/tiff" ;;
        bmp)             echo "image/bmp" ;;
        webp)            echo "image/webp" ;;
        pdf)             echo "application/pdf" ;;
        *)               echo "image/png" ;;
    esac
}

is_image() {
    local mime="$1"
    [[ "$mime" != "application/pdf" ]]
}

# ---------- main ----------

main() {
    local input_file=""
    local page=""
    local output_file=""

    # Parse arguments
    while (( $# )); do
        case "$1" in
            --help|-h)   usage ;;
            --page)      shift; page="${1:-}"; [ -z "$page" ] && error "--page requires a number" ;;
            --output|-o) shift; output_file="${1:-}"; [ -z "$output_file" ] && error "--output requires a filename" ;;
            -*)          error "Unknown option: $1" ;;
            *)           [ -z "$input_file" ] && input_file="$1" || error "Unexpected argument: $1" ;;
        esac
        shift
    done

    [ -z "$input_file" ] && error "No input file specified. Use --help for usage."
    [ ! -f "$input_file" ] && error "File not found: $input_file"

    local mime
    mime=$(detect_mime "$input_file")

    # Check if pdftoppm is needed
    if [[ "$mime" == "application/pdf" ]]; then
        NEED_PDFTOPPM=1
    fi

    check_deps
    load_config
    check_health

    # Redirect stdout to file if --output is set
    if [ -n "$output_file" ]; then
        exec > "$output_file"
        info "Output will be written to $output_file"
    fi

    if is_image "$mime"; then
        # Direct image — send as-is
        [ -n "$page" ] && warn "--page ignored for image files"
        info "Processing image: $input_file"
        ocr_image "$input_file" "$mime"
    else
        # PDF — convert pages to PNG, then OCR each
        local tmpdir
        tmpdir=$(mktemp -d)
        trap 'rm -rf "${tmpdir:-}"' EXIT

        if [ -n "$page" ]; then
            info "Converting PDF page $page to image..."
            pdftoppm -png -f "$page" -l "$page" -r 150 "$input_file" "$tmpdir/page"
        else
            info "Converting PDF pages to images..."
            pdftoppm -png -r 150 "$input_file" "$tmpdir/page"
        fi

        # Collect converted page images
        local existing_pages=()
        local f
        for f in "$tmpdir"/page*.png; do
            [ -f "$f" ] && existing_pages+=("$f")
        done

        if (( ${#existing_pages[@]} == 0 )); then
            error "No pages were converted. Check the PDF file."
        fi

        # Sort pages naturally (using a temp array to avoid subshell trap issues)
        local sorted_pages=()
        while IFS= read -r line; do
            sorted_pages+=("$line")
        done < <(printf '%s\n' "${existing_pages[@]}" | sort -V)
        existing_pages=("${sorted_pages[@]}")

        local total=${#existing_pages[@]}
        local i=0
        for page_file in "${existing_pages[@]}"; do
            (( i++ )) || true
            info "Processing page $i/$total..."
            if (( i > 1 )); then
                echo ""
                echo "--- Page $i ---"
                echo ""
            fi
            ocr_image "$page_file" "image/png"
        done

        info "Done. Processed $total page(s)."
    fi
}

main "$@"
