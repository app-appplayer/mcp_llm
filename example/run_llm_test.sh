#!/bin/bash
# LLM MCP test execution script

# Default settings
PORT=8999
AUTH_TOKEN="test_token"
MAX_RETRIES=5
MODE="sse"
LLM_PROVIDER="echo"
TEMPERATURE="0.7"
MAX_TOKENS="2000"
SERVER_WAIT=3
LOGS_DIR="./logs"

# Server/client mode settings
SERVER_ONLY=0
CLIENT_ONLY=0

# Log directory and file setup
mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
SERVER_LOG="$LOGS_DIR/llm_server_$TIMESTAMP.log"
CLIENT_LOG="$LOGS_DIR/llm_client_$TIMESTAMP.log"

# Help display
show_help() {
  echo "LLM MCP Test Execution Script"
  echo ""
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help                 Display help"
  echo "  -p, --port NUMBER          Specify port number (default: 8999, SSE mode only)"
  echo "  -a, --auth-token TOKEN     Specify authentication token (default: test_token)"
  echo "  -r, --retries NUMBER       Maximum retry attempts (default: 5)"
  echo "  -m, --mode MODE            Specify transmission mode (sse or stdio, default: sse)"
  echo "  -s, --server-only          Run server only"
  echo "  -c, --client-only          Run client only (in SSE mode, server must be already running)"
  echo "  -l, --llm-provider NAME    Specify LLM provider (default: echo)"
  echo "  -t, --temperature NUMBER   Set LLM temperature (default: 0.7)"
  echo "  -k, --max-tokens NUMBER    Set maximum tokens (default: 2000)"
  echo "  -w, --wait NUMBER          Specify server wait time in seconds (default: 3)"
  echo ""
  echo "Examples:"
  echo "  $0 --port 8888 --auth-token my_token --mode sse"
  echo "  $0 --server-only --llm-provider claude"
  echo "  $0 --client-only --max-retries 10"
}

# Command line argument parsing
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      show_help
      exit 0
      ;;
    -p|--port)
      PORT="$2"
      shift 2
      ;;
    -a|--auth-token)
      AUTH_TOKEN="$2"
      shift 2
      ;;
    -r|--retries)
      MAX_RETRIES="$2"
      shift 2
      ;;
    -m|--mode)
      MODE="$2"
      shift 2
      ;;
    -s|--server-only)
      SERVER_ONLY=1
      shift
      ;;
    -c|--client-only)
      CLIENT_ONLY=1
      shift
      ;;
    -l|--llm-provider)
      LLM_PROVIDER="$2"
      shift 2
      ;;
    -t|--temperature)
      TEMPERATURE="$2"
      shift 2
      ;;
    -k|--max-tokens)
      MAX_TOKENS="$2"
      shift 2
      ;;
    -w|--wait)
      SERVER_WAIT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# Function to wait for text in a file
wait_for_text() {
  local file=$1
  local text=$2
  local timeout=${3:-30}  # Default timeout 30 seconds

  echo "Waiting for text \"$text\" in [$file] (timeout: ${timeout} seconds)..."
  local start_time=$(date +%s)
  local end_time=$((start_time + timeout))

  while [ $(date +%s) -lt $end_time ]; do
    if grep -q "$text" "$file"; then
      echo "Found \"$text\" in [$file]!"
      return 0
    fi
    sleep 0.5
  done

  echo "Timeout waiting for \"$text\" in [$file]!"
  return 1
}

# Process termination function
cleanup() {
  echo "Cleaning up..."
  if [ ! -z "$SERVER_PID" ]; then
    echo "Terminating server process (PID: $SERVER_PID)..."
    kill $SERVER_PID 2>/dev/null || true
  fi
  echo "Done!"
}

# Setup cleanup trap
trap cleanup EXIT

echo "===== Starting LLM MCP Test ====="
echo "Mode: $MODE"
echo "Port: $PORT (SSE mode only)"
echo "Auth Token: $AUTH_TOKEN"
echo "Max Retries: $MAX_RETRIES"
echo "LLM Provider: $LLM_PROVIDER"
echo "Temperature: $TEMPERATURE"
echo "Max Tokens: $MAX_TOKENS"
echo ""

# Start server in SSE mode
if [ "$MODE" = "sse" ] && [ $CLIENT_ONLY -eq 0 ]; then
  echo "Starting server in SSE mode..."

  dart test_llm_server.dart \
    --port $PORT \
    --auth-token "$AUTH_TOKEN" \
    --llm-provider "$LLM_PROVIDER" \
    --temperature "$TEMPERATURE" \
    --max-tokens "$MAX_TOKENS" \
    > "$SERVER_LOG" 2>&1 &

  SERVER_PID=$!
  echo "Server started (PID: $SERVER_PID)"

  # Wait for server to be ready
  if ! wait_for_text "$SERVER_LOG" "SSE server running at:" $SERVER_WAIT; then
    echo "Server startup failed! Check log: $SERVER_LOG"
    exit 1
  fi

  echo "Server ready"
fi

# Run server only in STDIO mode
if [ "$MODE" = "stdio" ] && [ $SERVER_ONLY -eq 1 ]; then
  echo "Starting server in STDIO mode..."
  dart test_llm_server.dart \
    --mode stdio \
    --auth-token "$AUTH_TOKEN" \
    --llm-provider "$LLM_PROVIDER" \
    --temperature "$TEMPERATURE" \
    --max-tokens "$MAX_TOKENS"
  exit 0
fi

# Server-only mode
if [ $SERVER_ONLY -eq 1 ]; then
  echo "Running in server-only mode. Press Ctrl+C to exit..."
  # Show server logs in real-time
  tail -f "$SERVER_LOG"
  # User exits with Ctrl+C which triggers the trap function
  exit 0
fi

# Run client (if not in server-only mode)
if [ $SERVER_ONLY -eq 0 ]; then
  echo "Starting client..."

  dart test_llm_client.dart \
    --mode $MODE \
    --port $PORT \
    --auth-token "$AUTH_TOKEN" \
    --max-retries $MAX_RETRIES \
    --llm-provider "$LLM_PROVIDER" \
    --temperature "$TEMPERATURE" \
    --max-tokens "$MAX_TOKENS" \
    | tee "$CLIENT_LOG"

  CLIENT_EXIT_CODE=$?
  echo "Client terminated (exit code: $CLIENT_EXIT_CODE)"
fi

echo "===== LLM MCP Test Complete ====="
echo "Log files:"
echo "- Server log: $SERVER_LOG"
echo "- Client log: $CLIENT_LOG"

exit ${CLIENT_EXIT_CODE:-0}
