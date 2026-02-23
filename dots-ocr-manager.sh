#!/bin/bash

# dots-ocr-manager.sh
# Management script for dots.ocr with vLLM
# Version: 2.0.0

# Change to script directory to find docker-compose.yml
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Project name
COMPOSE_PROJECT="dots-ocr"

# Detected compose command
COMPOSE_CMD=""

# Check if docker compose is installed and store the command
check_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif docker-compose --version >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    else
        echo "Error: docker compose is not installed"
        echo "Please install Docker and Docker Compose v2.x"
        exit 1
    fi
}

# Run compose command with configured project name
run_compose() {
    $COMPOSE_CMD -p "$COMPOSE_PROJECT" "$@"
}

# Detect the active container name (GPU or CPU)
get_container_name() {
    if docker inspect dots-ocr-service >/dev/null 2>&1; then
        echo "dots-ocr-service"
    elif docker inspect dots-ocr-cpu-service >/dev/null 2>&1; then
        echo "dots-ocr-cpu-service"
    else
        echo ""
    fi
}

# Detect the active compose service name
get_service_name() {
    local container
    container=$(get_container_name)
    if [ "$container" = "dots-ocr-cpu-service" ]; then
        echo "dots-ocr-cpu"
    else
        echo "dots-ocr"
    fi
}

# Print colored messages
print_message() {
    local color=$1
    local message=$2
    local reset='\033[0m'

    case $color in
        "green") echo -e "\033[32m${message}${reset}" ;;
        "yellow") echo -e "\033[33m${message}${reset}" ;;
        "blue") echo -e "\033[34m${message}${reset}" ;;
        "red") echo -e "\033[31m${message}${reset}" ;;
        *) echo -e "${message}" ;;
    esac
}

# Show help
show_help() {
    echo "=========================================="
    echo "  dots-ocr-manager.sh - Management Script"
    echo "=========================================="
    echo ""
    echo "Usage: ./dots-ocr-manager.sh <command> [options]"
    echo ""
    echo "Commands:"
    echo "  up [--cpu] - Start dots.ocr (GPU default, --cpu for CPU-only)"
    echo "  down       - Stop dots.ocr"
    echo "  restart    - Restart dots.ocr"
    echo "  logs       - Show real-time logs"
    echo "  status     - Show container status and GPU usage"
    echo "  pull       - Update Docker image"
    echo "  exec       - Open a shell in the container"
    echo "  update     - Update everything (pull + down + up)"
    echo "  clean      - Full cleanup (down + remove volumes)"
    echo "  test       - Test the API with a sample image"
    echo "  help       - Show this help"
    echo ""
    echo "Hardware profiles:"
    echo "  cp examples/env.gpu-24gb .env   # GPU >= 24GB VRAM (full model)"
    echo "  cp examples/env.gpu-12gb .env   # GPU 12GB VRAM (bitsandbytes)"
    echo "  cp examples/env.cpu .env        # CPU-only (slow, no GPU)"
    echo ""
    echo "Examples:"
    echo "  ./dots-ocr-manager.sh up         # Start with GPU"
    echo "  ./dots-ocr-manager.sh up --cpu   # Start without GPU (CPU-only)"
    echo "  ./dots-ocr-manager.sh logs"
    echo "  ./dots-ocr-manager.sh status"
    echo ""
    echo "NOTE: This script can be run from any directory."
    echo "      Copy .env.example to .env and customize the variables."
    echo "=========================================="
}

# Start dots.ocr
cmd_up() {
    local use_cpu=false
    if [ "$1" = "--cpu" ]; then
        use_cpu=true
    fi

    # Check if a container is already running
    local containers
    containers=$(run_compose ps -q 2>/dev/null)
    if [ -n "$containers" ]; then
        print_message "yellow" "dots.ocr is already running"
        run_compose ps
        return
    fi

    if [ "$use_cpu" = true ]; then
        print_message "blue" "Starting dots.ocr in CPU-only mode..."
        print_message "yellow" "WARNING: CPU mode is much slower than GPU"
        run_compose --profile cpu up -d dots-ocr-cpu
    else
        print_message "blue" "Starting dots.ocr with GPU..."
        run_compose up -d dots-ocr
    fi

    echo ""
    print_message "green" "dots.ocr has been started!"
    echo ""
    print_message "yellow" "OpenAI-compatible API access:"
    echo "   Base URL: http://localhost:8000/v1"
    echo "   Model name: dots-ocr"
    echo ""
    print_message "yellow" "The model is loading, check the logs:"
    echo "   ./dots-ocr-manager.sh logs"
}

# Stop dots.ocr
cmd_down() {
    print_message "blue" "Stopping dots.ocr..."

    # Stop both GPU and CPU profiles
    run_compose --profile cpu down
    echo ""
    print_message "green" "dots.ocr has been stopped"
}

# Restart dots.ocr
cmd_restart() {
    print_message "blue" "Restarting dots.ocr..."

    local service
    service=$(get_service_name)

    if run_compose restart "$service"; then
        print_message "green" "dots.ocr has been restarted"
    else
        print_message "red" "Error during restart"
        exit 1
    fi
}

# Show logs
cmd_logs() {
    local service
    service=$(get_service_name)

    print_message "blue" "Showing dots.ocr logs (Ctrl+C to exit)..."
    run_compose logs -f "$service"
}

# Pull latest image
cmd_pull() {
    print_message "blue" "Pulling latest Docker image..."

    if run_compose pull; then
        print_message "green" "Image updated successfully"
        print_message "yellow" "Run './dots-ocr-manager.sh update' to apply changes"
    else
        print_message "red" "Error during pull"
        exit 1
    fi
}

# Show status
cmd_status() {
    print_message "blue" "dots.ocr status:"
    echo ""

    # Container status
    local container
    container=$(get_container_name)

    if [ -n "$container" ]; then
        run_compose ps
    else
        print_message "yellow" "No container running"
    fi

    echo ""

    # GPU checks (on the host)
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi
    else
        print_message "yellow" "nvidia-smi not available on the host"
    fi

    echo ""
    print_message "yellow" "Healthcheck:"

    if [ -z "$container" ]; then
        print_message "yellow" "   Healthcheck not available (container not running)"
        return
    fi

    if docker inspect --format='{{.State.Health.Status}}' "$container" >/dev/null 2>&1; then
        HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container")
        case $HEALTH_STATUS in
            "healthy") print_message "green" "   Status: ${HEALTH_STATUS}" ;;
            "unhealthy") print_message "red" "   Status: ${HEALTH_STATUS}" ;;
            "starting") print_message "yellow" "   Status: ${HEALTH_STATUS}" ;;
            *) print_message "yellow" "   Status: ${HEALTH_STATUS}" ;;
        esac
    else
        print_message "yellow" "   Healthcheck not available"
    fi
}

# Open shell in container
cmd_exec() {
    local service
    service=$(get_service_name)

    print_message "blue" "Opening shell in the container..."

    if run_compose exec "$service" /bin/bash; then
        echo ""
    else
        print_message "red" "Error during exec"
        exit 1
    fi
}

# Update everything
cmd_update() {
    print_message "blue" "Updating dots.ocr..."
    echo ""

    print_message "yellow" "1. Pulling latest image..."
    if ! run_compose pull; then
        print_message "red" "Error during pull"
        exit 1
    fi

    echo ""
    print_message "yellow" "2. Stopping service..."
    if ! run_compose --profile cpu down; then
        print_message "red" "Error during stop"
        exit 1
    fi

    echo ""
    print_message "yellow" "3. Starting service..."
    if ! run_compose up -d; then
        print_message "red" "Error during start"
        exit 1
    fi

    echo ""
    print_message "green" "dots.ocr has been updated successfully!"
    print_message "yellow" "To check status:"
    echo "   ./dots-ocr-manager.sh status"
}

# Full cleanup
cmd_clean() {
    print_message "blue" "Full cleanup..."

    read -p "Are you sure you want to completely remove dots.ocr (including volumes)? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_compose --profile cpu down -v
        print_message "green" "Cleanup completed"
    else
        print_message "yellow" "Cleanup cancelled"
    fi
}

# Test the API with a sample image
cmd_test() {
    print_message "blue" "Testing dots.ocr API..."
    echo ""

    # Detect active container
    local container
    container=$(get_container_name)

    if [ -z "$container" ]; then
        print_message "red" "No active container. Start it with: ./dots-ocr-manager.sh up"
        exit 1
    fi

    # Check health
    if docker inspect --format='{{.State.Health.Status}}' "$container" >/dev/null 2>&1; then
        HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container")
        if [ "$HEALTH_STATUS" != "healthy" ]; then
            print_message "yellow" "Service is not yet healthy (status: $HEALTH_STATUS)"
            print_message "yellow" "Wait for the model to fully load and try again."
            exit 1
        fi
    fi

    # Check that the test file exists (PNG preferred, PDF as fallback)
    local test_file="$SCRIPT_DIR/test/sample.png"
    local mime_type="image/png"
    if [ ! -f "$test_file" ]; then
        test_file="$SCRIPT_DIR/test/sample.pdf"
        mime_type="application/pdf"
    fi
    if [ ! -f "$test_file" ]; then
        print_message "red" "Test file not found in test/"
        exit 1
    fi

    # Read token from .env or use default
    local api_token="${VLLM_TOKEN:-your-secret-token-here}"
    if [ -f "$SCRIPT_DIR/.env" ]; then
        local env_token
        env_token=$(grep -E '^VLLM_TOKEN=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2-)
        if [ -n "$env_token" ]; then
            api_token="$env_token"
        fi
    fi

    local api_port="${API_PORT:-8000}"
    if [ -f "$SCRIPT_DIR/.env" ]; then
        local env_port
        env_port=$(grep -E '^API_PORT=' "$SCRIPT_DIR/.env" 2>/dev/null | cut -d'=' -f2-)
        if [ -n "$env_port" ]; then
            api_port="$env_port"
        fi
    fi

    # Encode file to base64
    print_message "yellow" "Sending test image to the API..."
    local file_base64
    file_base64=$(base64 -w 0 "$test_file")

    # Send request to OpenAI-compatible API
    local response
    response=$(curl -s -w "\n%{http_code}" --max-time 120 \
        -X POST "http://localhost:${api_port}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${api_token}" \
        -d "{
            \"model\": \"dots-ocr\",
            \"messages\": [
                {
                    \"role\": \"user\",
                    \"content\": [
                        {
                            \"type\": \"image_url\",
                            \"image_url\": {
                                \"url\": \"data:${mime_type};base64,${file_base64}\"
                            }
                        },
                        {
                            \"type\": \"text\",
                            \"text\": \"Extract all text from this document.\"
                        }
                    ]
                }
            ],
            \"max_tokens\": 2048
        }")

    # Separate body and HTTP status code
    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    echo ""
    if [ "$http_code" = "200" ]; then
        print_message "green" "Test completed successfully! (HTTP $http_code)"
        echo ""
        print_message "yellow" "Text extracted by OCR model:"
        echo "---"
        echo "$body" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['choices'][0]['message']['content'])" 2>/dev/null || echo "$body"
        echo "---"
    else
        print_message "red" "Test failed! (HTTP $http_code)"
        echo ""
        echo "$body"
        exit 1
    fi
}

# Main function
main() {
    # Check arguments
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    # Check docker compose
    check_docker_compose

    # Execute command
    case "$1" in
        up)
            cmd_up "$2"
            ;;
        down)
            cmd_down
            ;;
        restart)
            cmd_restart
            ;;
        logs)
            cmd_logs
            ;;
        status)
            cmd_status
            ;;
        pull)
            cmd_pull
            ;;
        exec)
            cmd_exec
            ;;
        update)
            cmd_update
            ;;
        clean)
            cmd_clean
            ;;
        test)
            cmd_test
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_message "red" "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run
main "$@"
