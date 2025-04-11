#!/bin/bash
# LLM MCP server execution script

PORT=8999
AUTH_TOKEN="test_token"
MODE="sse"
LLM_PROVIDER="echo"
TEMPERATURE="0.7"
MAX_TOKENS="2000"
SERVER_WAIT=3
LOGS_DIR="./logs"

mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
SERVER_LOG="$LOGS_DIR/llm_server_$TIMESTAMP.log"

wait_for_text() {
  local file=$1
  local text=$2
  local timeout=${3:-30}
  echo "Waiting for \"$text\" in [$file]..."
  local end_time=$(( $(date +%s) + timeout ))

  while [ $(date +%s) -lt $end_time ]; do
    if grep -q "$text" "$file"; then
      echo "\"$text\" found!"
      return 0
    fi
    sleep 0.5
  done

  echo "Timeout occurred!"
  return 1
}

cleanup() {
  echo "Shutting down server..."
  if [ ! -z "$SERVER_PID" ]; then
    kill $SERVER_PID 2>/dev/null || true
  fi
  echo "Shutdown complete"
}
trap cleanup EXIT

echo "===== Starting LLM server ====="
echo "Mode: $MODE / Port: $PORT / LLM: $LLM_PROVIDER"

dart test_llm_server.dart \
  --port $PORT \
  --auth-token "$AUTH_TOKEN" \
  --llm-provider "$LLM_PROVIDER" \
  --temperature "$TEMPERATURE" \
  --max-tokens "$MAX_TOKENS" \
  > "$SERVER_LOG" 2>&1 &

SERVER_PID=$!
echo "Server PID: $SERVER_PID"

if ! wait_for_text "$SERVER_LOG" "SSE server running at:" $SERVER_WAIT; then
  echo "Server startup failed! Check log: $SERVER_LOG"
  exit 1
fi

echo "Server running. Showing log output..."
tail -f "$SERVER_LOG"
