# dots.ocr - Dockerized OCR with vLLM

<a href="https://www.buymeacoffee.com/manzolo">
  <img src=".github/blue-button.png" alt="Buy Me A Coffee" width="200">
</a>

A Docker setup for running [dots.ocr](https://github.com/rednote-hilab/dots.ocr), a vision-language model for document OCR, powered by [vLLM](https://github.com/vllm-project/vllm). Exposes an OpenAI-compatible API for extracting text from images and PDFs.

Upload an image or PDF, and the model returns the text it contains — useful for digitizing scanned documents, invoices, receipts, and any printed or handwritten text. Works on GPU (fast) or CPU-only (slower). Includes a management script and a standalone tool for batch PDF processing.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and Docker Compose v2
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (for GPU mode only)

## Quick Start

1. Clone the repository:
```bash
git clone https://github.com/manzolo/dots.ocr-docker.git
cd dots.ocr-docker
```

2. Copy the example env for your hardware:
```bash
cp examples/env.gpu-24gb .env   # GPU >= 24GB VRAM
cp examples/env.gpu-12gb .env   # GPU 12GB VRAM (bitsandbytes)
cp examples/env.cpu .env        # CPU-only (slow)
```

3. **CPU-only**: build the CPU image first (one-time, ~15-30 min):
```bash
./dots-ocr-manager.sh build-cpu
```

4. Start the service:
```bash
./dots-ocr-manager.sh up          # GPU mode
./dots-ocr-manager.sh up --cpu    # CPU-only mode
```

5. Wait for the model to load, then test:
```bash
./dots-ocr-manager.sh test
```

## Usage

### Management Script

```bash
./dots-ocr-manager.sh up [--cpu]   # Start (GPU default, --cpu for CPU-only)
./dots-ocr-manager.sh down         # Stop
./dots-ocr-manager.sh restart      # Restart
./dots-ocr-manager.sh logs         # Show real-time logs
./dots-ocr-manager.sh status       # Container status + GPU info
./dots-ocr-manager.sh test         # Test API with sample image
./dots-ocr-manager.sh pull         # Pull latest Docker image
./dots-ocr-manager.sh update       # Pull + restart
./dots-ocr-manager.sh build-cpu    # Build CPU image from vLLM source
./dots-ocr-manager.sh clean        # Remove everything including volumes
./dots-ocr-manager.sh help         # Show help
```

### API Example

Once the service is healthy, send requests to the OpenAI-compatible API:

```bash
# Encode an image to base64
IMAGE_B64=$(base64 -w 0 your-image.png)

# Extract text
curl -s http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your-secret-token-here" \
  -d "{
    \"model\": \"dots-ocr\",
    \"messages\": [{
      \"role\": \"user\",
      \"content\": [
        {\"type\": \"image_url\", \"image_url\": {\"url\": \"data:image/png;base64,${IMAGE_B64}\"}},
        {\"type\": \"text\", \"text\": \"Extract all text from this document.\"}
      ]
    }],
    \"max_tokens\": 2048
  }"
```

### PDF Processing

A standalone script that converts each PDF page to an image (`pdftoppm`), sends it to the OCR API, and outputs the extracted text. Also works directly with image files. Requires `poppler-utils`.

```bash
# OCR all pages of a PDF
./pdf-ocr.sh document.pdf

# OCR a single page
./pdf-ocr.sh document.pdf --page 2

# Save output to a file
./pdf-ocr.sh document.pdf --output result.txt

# Works with images too
./pdf-ocr.sh photo.png
```

## Hardware Profiles

| Profile | GPU VRAM | Quantization | Model Length | Example GPUs |
|---------|----------|--------------|-------------|--------------|
| `env.gpu-24gb` | >= 24 GB | None (full) | 8192 | RTX 3090, RTX 4090, A5000 |
| `env.gpu-12gb` | 12 GB | bitsandbytes | 4096 | RTX 3080 Ti, RTX 4070 |
| `env.cpu` | N/A | None (float32) | 4096 | Any CPU |

## Volume Mounts

| Volume | Container Path | Description |
|--------|----------------|-------------|
| `huggingface-cache` | `/root/.cache/huggingface` | Cached model weights (persisted between runs) |
| `ocr-logs` | `/var/log/vllm` | vLLM log files |

## Models

| Model | Size | Description |
|-------|------|-------------|
| `rednote-hilab/dots.ocr` | ~3.5 GB | Standard model, best accuracy |
| `sugam24/dots-ocr-awq-4bit` | ~0.8 GB | AWQ 4-bit quantized, lower VRAM |

## References

- [dots.ocr GitHub Repository](https://github.com/rednote-hilab/dots.ocr)
- [vLLM Documentation](https://docs.vllm.ai/)
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- [Docker Official Website](https://docs.docker.com/get-docker/)
