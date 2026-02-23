#!/bin/bash

# dots-ocr-manager.sh
# Script di gestione per dots.ocr con vLLM
# Versione: 1.2.0

# Cambia alla directory dello script per trovare docker-compose.yml
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Nome del progetto
COMPOSE_PROJECT="dots-ocr"

# Variabile per il comando compose rilevato
COMPOSE_CMD=""

# Funzione per verificare se docker compose e' installato e salvare il comando
check_docker_compose() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif docker-compose --version >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    else
        echo "Errore: docker compose non e' installato"
        echo "Per favore installa Docker e Docker Compose v2.x"
        exit 1
    fi
}

# Esegue il comando compose con il progetto configurato
run_compose() {
    $COMPOSE_CMD -p "$COMPOSE_PROJECT" "$@"
}

# Rileva il nome del container attivo (GPU o CPU)
get_container_name() {
    if docker inspect dots-ocr-service >/dev/null 2>&1; then
        echo "dots-ocr-service"
    elif docker inspect dots-ocr-cpu-service >/dev/null 2>&1; then
        echo "dots-ocr-cpu-service"
    else
        echo ""
    fi
}

# Rileva il nome del servizio compose attivo
get_service_name() {
    local container
    container=$(get_container_name)
    if [ "$container" = "dots-ocr-cpu-service" ]; then
        echo "dots-ocr-cpu"
    else
        echo "dots-ocr"
    fi
}

# Funzione per stampare messaggi colorati
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

# Funzione per mostrare aiuto
show_help() {
    echo "=========================================="
    echo "  dots-ocr-manager.sh - Script di gestione"
    echo "=========================================="
    echo ""
    echo "Uso: ./dots-ocr-manager.sh <comando> [opzioni]"
    echo ""
    echo "Comandi disponibili:"
    echo "  up [--cpu] - Avvia dots.ocr (GPU default, --cpu per CPU-only)"
    echo "  down      - Ferma dots.ocr"
    echo "  restart   - Riavvia dots.ocr"
    echo "  logs      - Visualizza i log in tempo reale"
    echo "  status    - Mostra stato del container e utilizzo GPU"
    echo "  pull      - Aggiorna l'immagine Docker"
    echo "  exec      - Entra nella shell del container"
    echo "  update    - Aggiorna tutto (pull + down + up)"
    echo "  clean     - Pulisce completamente (down + rm volumes)"
    echo "  test      - Testa l'API con un PDF di esempio"
    echo "  help      - Mostra questo aiuto"
    echo ""
    echo "Esempi:"
    echo "  ./dots-ocr-manager.sh up          # Avvia con GPU"
    echo "  ./dots-ocr-manager.sh up --cpu    # Avvia senza GPU (CPU-only)"
    echo "  ./dots-ocr-manager.sh logs"
    echo "  ./dots-ocr-manager.sh status"
    echo ""
    echo "NOTA: Lo script puo' essere lanciato da qualsiasi directory."
    echo "      Copia .env.example in .env e personalizza le variabili."
    echo "=========================================="
}

# Funzione per avviare dots.ocr
cmd_up() {
    local use_cpu=false
    if [ "$1" = "--cpu" ]; then
        use_cpu=true
    fi

    # Controlla se c'e' gia' un container attivo
    local containers
    containers=$(run_compose ps -q 2>/dev/null)
    if [ -n "$containers" ]; then
        print_message "yellow" "dots.ocr e' gia' in esecuzione"
        run_compose ps
        return
    fi

    if [ "$use_cpu" = true ]; then
        print_message "blue" "Avvio dots.ocr in modalita' CPU-only..."
        print_message "yellow" "ATTENZIONE: la modalita' CPU e' molto piu' lenta della GPU"
        run_compose --profile cpu up -d dots-ocr-cpu
    else
        print_message "blue" "Avvio dots.ocr con GPU..."
        run_compose up -d dots-ocr
    fi

    echo ""
    print_message "green" "dots.ocr e' stato avviato!"
    echo ""
    print_message "yellow" "Accesso API OpenAI-compatible:"
    echo "   Base URL: http://localhost:8000/v1"
    echo "   Model name: dots-ocr"
    echo ""
    print_message "yellow" "Il modello si sta caricando, controlla i log:"
    echo "   ./dots-ocr-manager.sh logs"
}

# Funzione per fermare dots.ocr
cmd_down() {
    print_message "blue" "Fermata dots.ocr..."

    # Ferma sia GPU che CPU profile
    run_compose --profile cpu down
    echo ""
    print_message "green" "dots.ocr e' stato fermato"
}

# Funzione per riavviare dots.ocr
cmd_restart() {
    print_message "blue" "Riavvio dots.ocr..."

    local service
    service=$(get_service_name)

    if run_compose restart "$service"; then
        print_message "green" "dots.ocr e' stato riavviato"
    else
        print_message "red" "Errore durante il riavvio"
        exit 1
    fi
}

# Funzione per visualizzare i log
cmd_logs() {
    local service
    service=$(get_service_name)

    print_message "blue" "Visualizzazione log di dots.ocr (Ctrl+C per uscire)..."
    run_compose logs -f "$service"
}

# Funzione per aggiornare l'immagine
cmd_pull() {
    print_message "blue" "Pull dell'ultima immagine Docker..."

    if run_compose pull; then
        print_message "green" "Immagine aggiornata con successo"
        print_message "yellow" "Esegui './dots-ocr-manager.sh update' per applicare le modifiche"
    else
        print_message "red" "Errore durante il pull"
        exit 1
    fi
}

# Funzione per mostrare lo stato
cmd_status() {
    print_message "blue" "Status di dots.ocr:"
    echo ""

    # Stato container
    local container
    container=$(get_container_name)

    if [ -n "$container" ]; then
        run_compose ps
    else
        print_message "yellow" "Nessun container in esecuzione"
    fi

    echo ""

    # Controlli GPU (direttamente sull'host)
    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi
    else
        print_message "yellow" "nvidia-smi non disponibile sull'host"
    fi

    echo ""
    print_message "yellow" "Healthcheck:"

    if [ -z "$container" ]; then
        print_message "yellow" "   Healthcheck non disponibile (container non attivo)"
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
        print_message "yellow" "   Healthcheck non disponibile"
    fi
}

# Funzione per entrare nel container
cmd_exec() {
    local service
    service=$(get_service_name)

    print_message "blue" "Accesso alla shell del container..."

    if run_compose exec "$service" /bin/bash; then
        echo ""
    else
        print_message "red" "Errore durante l'esecuzione"
        exit 1
    fi
}

# Funzione per aggiornare tutto
cmd_update() {
    print_message "blue" "Aggiornamento dots.ocr..."
    echo ""

    print_message "yellow" "1. Pull dell'ultima immagine..."
    if ! run_compose pull; then
        print_message "red" "Errore durante il pull"
        exit 1
    fi

    echo ""
    print_message "yellow" "2. Fermata del servizio..."
    if ! run_compose --profile cpu down; then
        print_message "red" "Errore durante la fermata"
        exit 1
    fi

    echo ""
    print_message "yellow" "3. Avvio del servizio..."
    if ! run_compose up -d; then
        print_message "red" "Errore durante l'avvio"
        exit 1
    fi

    echo ""
    print_message "green" "dots.ocr e' stato aggiornato con successo!"
    print_message "yellow" "Per verificare lo stato:"
    echo "   ./dots-ocr-manager.sh status"
}

# Funzione per pulire tutto
cmd_clean() {
    print_message "blue" "Pulizia completa..."

    read -p "Sei sicuro di voler rimuovere completamente dots.ocr (inclusi i volumi)? (s/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        run_compose --profile cpu down -v
        print_message "green" "Pulizia completata"
    else
        print_message "yellow" "Pulizia annullata"
    fi
}

# Funzione per testare l'API con un PDF di esempio
cmd_test() {
    print_message "blue" "Test dell'API dots.ocr..."
    echo ""

    # Rileva il container attivo
    local container
    container=$(get_container_name)

    if [ -z "$container" ]; then
        print_message "red" "Nessun container attivo. Avvialo con: ./dots-ocr-manager.sh up"
        exit 1
    fi

    # Verifica health
    if docker inspect --format='{{.State.Health.Status}}' "$container" >/dev/null 2>&1; then
        HEALTH_STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container")
        if [ "$HEALTH_STATUS" != "healthy" ]; then
            print_message "yellow" "Il servizio non e' ancora healthy (status: $HEALTH_STATUS)"
            print_message "yellow" "Attendi che il modello sia completamente caricato e riprova."
            exit 1
        fi
    fi

    # Verifica che il file di test esista (PNG preferito, PDF come fallback)
    local test_file="$SCRIPT_DIR/test/sample.png"
    local mime_type="image/png"
    if [ ! -f "$test_file" ]; then
        test_file="$SCRIPT_DIR/test/sample.pdf"
        mime_type="application/pdf"
    fi
    if [ ! -f "$test_file" ]; then
        print_message "red" "File di test non trovato in test/"
        exit 1
    fi

    # Leggi il token dal .env o usa il default
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

    # Codifica il file in base64
    print_message "yellow" "Invio immagine di test all'API..."
    local file_base64
    file_base64=$(base64 -w 0 "$test_file")

    # Invia la richiesta all'API OpenAI-compatible
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

    # Separa body e HTTP status code
    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    echo ""
    if [ "$http_code" = "200" ]; then
        print_message "green" "Test completato con successo! (HTTP $http_code)"
        echo ""
        print_message "yellow" "Testo estratto dal modello OCR:"
        echo "---"
        echo "$body" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['choices'][0]['message']['content'])" 2>/dev/null || echo "$body"
        echo "---"
    else
        print_message "red" "Test fallito! (HTTP $http_code)"
        echo ""
        echo "$body"
        exit 1
    fi
}

# Funzione principale
main() {
    # Verifica argomenti
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    # Verifica docker compose
    check_docker_compose

    # Esegui comando
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
            print_message "red" "Comando sconosciuto: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Esecuzione
main "$@"
