#!/bin/bash
# LLM MCP 서버 실행 스크립트

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
  echo "[$file]에서 \"$text\" 대기 중..."
  local end_time=$(( $(date +%s) + timeout ))

  while [ $(date +%s) -lt $end_time ]; do
    if grep -q "$text" "$file"; then
      echo "\"$text\" 발견됨!"
      return 0
    fi
    sleep 0.5
  done

  echo "타임아웃 발생!"
  return 1
}

cleanup() {
  echo "서버 종료 중..."
  if [ ! -z "$SERVER_PID" ]; then
    kill $SERVER_PID 2>/dev/null || true
  fi
  echo "종료 완료"
}
trap cleanup EXIT

echo "===== LLM 서버 시작 ====="
echo "모드: $MODE / 포트: $PORT / LLM: $LLM_PROVIDER"

dart test_llm_server.dart \
  --port $PORT \
  --auth-token "$AUTH_TOKEN" \
  --llm-provider "$LLM_PROVIDER" \
  --temperature "$TEMPERATURE" \
  --max-tokens "$MAX_TOKENS" \
  > "$SERVER_LOG" 2>&1 &

SERVER_PID=$!
echo "서버 PID: $SERVER_PID"

if ! wait_for_text "$SERVER_LOG" "SSE server running at:" $SERVER_WAIT; then
  echo "서버 시작 실패! 로그 확인: $SERVER_LOG"
  exit 1
fi

echo "서버 실행 중. 로그 출력 중..."
tail -f "$SERVER_LOG"
