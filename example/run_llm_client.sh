#!/bin/bash
# LLM MCP client execution script

PORT=8999
AUTH_TOKEN="test_token"
MAX_RETRIES=5
MODE="sse"
LLM_PROVIDER="echo"
TEMPERATURE="0.7"
MAX_TOKENS="2000"
LOGS_DIR="./logs"

mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
CLIENT_LOG="$LOGS_DIR/llm_client_$TIMESTAMP.log"

echo "===== Starting LLM client ====="
echo "Mode: $MODE / Port: $PORT / LLM: $LLM_PROVIDER"

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
echo "Client terminated (code: $CLIENT_EXIT_CODE)"
echo "Log file: $CLIENT_LOG"

exit $CLIENT_EXIT_CODE
