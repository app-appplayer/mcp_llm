#!/bin/bash
# LLM MCP 클라이언트 실행 스크립트

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

echo "===== LLM 클라이언트 시작 ====="
echo "모드: $MODE / 포트: $PORT / LLM: $LLM_PROVIDER"

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
echo "클라이언트 종료됨 (코드: $CLIENT_EXIT_CODE)"
echo "로그 파일: $CLIENT_LOG"

exit $CLIENT_EXIT_CODE
