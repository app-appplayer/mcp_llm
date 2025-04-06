#!/bin/bash
# LLM MCP 테스트 실행 스크립트

# 기본값 설정
PORT=8999
AUTH_TOKEN="test_token"
MAX_RETRIES=5
MODE="sse"
LLM_PROVIDER="echo"
TEMPERATURE="0.7"
MAX_TOKENS="2000"
SERVER_WAIT=3
LOGS_DIR="./logs"

# 서버/클라이언트 모드 설정
SERVER_ONLY=0
CLIENT_ONLY=0

# 로그 디렉토리 및 파일 설정
mkdir -p "$LOGS_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
SERVER_LOG="$LOGS_DIR/llm_server_$TIMESTAMP.log"
CLIENT_LOG="$LOGS_DIR/llm_client_$TIMESTAMP.log"

# 도움말 표시
show_help() {
  echo "LLM MCP 테스트 실행 스크립트"
  echo ""
  echo "사용법: $0 [옵션]"
  echo ""
  echo "옵션:"
  echo "  -h, --help                 도움말 표시"
  echo "  -p, --port NUMBER          포트 번호 지정 (기본값: 8999, SSE 모드만 해당)"
  echo "  -a, --auth-token TOKEN     인증 토큰 지정 (기본값: test_token)"
  echo "  -r, --retries NUMBER       최대 재시도 횟수 (기본값: 5)"
  echo "  -m, --mode MODE            전송 모드 지정 (sse 또는 stdio, 기본값: sse)"
  echo "  -s, --server-only          서버만 실행"
  echo "  -c, --client-only          클라이언트만 실행 (SSE 모드에서는 서버가 이미 실행 중이어야 함)"
  echo "  -l, --llm-provider NAME    LLM 제공자 지정 (기본값: echo)"
  echo "  -t, --temperature NUMBER   LLM 온도 설정 (기본값: 0.7)"
  echo "  -k, --max-tokens NUMBER    최대 토큰 수 설정 (기본값: 2000)"
  echo "  -w, --wait NUMBER          서버 대기 시간(초) 지정 (기본값: 3)"
  echo ""
  echo "예시:"
  echo "  $0 --port 8888 --auth-token my_token --mode sse"
  echo "  $0 --server-only --llm-provider claude"
  echo "  $0 --client-only --max-retries 10"
}

# 명령줄 인수 파싱
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
      echo "알 수 없는 옵션: $1"
      show_help
      exit 1
      ;;
  esac
done

# 파일에서 특정 텍스트를 기다리는 함수
wait_for_text() {
  local file=$1
  local text=$2
  local timeout=${3:-30}  # 기본 타임아웃 30초

  echo "[$file]에서 텍스트 \"$text\" 대기 중 (타임아웃: ${timeout}초)..."
  local start_time=$(date +%s)
  local end_time=$((start_time + timeout))

  while [ $(date +%s) -lt $end_time ]; do
    if grep -q "$text" "$file"; then
      echo "[$file]에서 \"$text\" 발견!"
      return 0
    fi
    sleep 0.5
  done

  echo "[$file]에서 \"$text\" 대기 타임아웃!"
  return 1
}

# 프로세스 종료 함수
cleanup() {
  echo "정리 중..."
  if [ ! -z "$SERVER_PID" ]; then
    echo "서버 프로세스 종료 중 (PID: $SERVER_PID)..."
    kill $SERVER_PID 2>/dev/null || true
  fi
  echo "완료!"
}

# 정리 트랩 설정
trap cleanup EXIT

echo "===== LLM MCP 테스트 시작 ====="
echo "모드: $MODE"
echo "포트: $PORT (SSE 모드만 해당)"
echo "인증 토큰: $AUTH_TOKEN"
echo "최대 재시도: $MAX_RETRIES"
echo "LLM 제공자: $LLM_PROVIDER"
echo "온도: $TEMPERATURE"
echo "최대 토큰: $MAX_TOKENS"
echo ""

# SSE 모드에서 서버 시작
if [ "$MODE" = "sse" ] && [ $CLIENT_ONLY -eq 0 ]; then
  echo "SSE 모드에서 서버 시작 중..."

  dart test_llm_server.dart \
    --port $PORT \
    --auth-token "$AUTH_TOKEN" \
    --llm-provider "$LLM_PROVIDER" \
    --temperature "$TEMPERATURE" \
    --max-tokens "$MAX_TOKENS" \
    > "$SERVER_LOG" 2>&1 &

  SERVER_PID=$!
  echo "서버 시작됨 (PID: $SERVER_PID)"

  # 서버가 준비될 때까지 대기
  if ! wait_for_text "$SERVER_LOG" "SSE server running at:" $SERVER_WAIT; then
    echo "서버 시작 실패! 로그 확인: $SERVER_LOG"
    exit 1
  fi

  echo "서버 시작 대기 완료"
fi

# STDIO 모드에서 서버만 실행
if [ "$MODE" = "stdio" ] && [ $SERVER_ONLY -eq 1 ]; then
  echo "STDIO 모드에서 서버 시작 중..."
  dart test_llm_server.dart \
    --mode stdio \
    --auth-token "$AUTH_TOKEN" \
    --llm-provider "$LLM_PROVIDER" \
    --temperature "$TEMPERATURE" \
    --max-tokens "$MAX_TOKENS"
  exit 0
fi

# 서버만 실행 모드
if [ $SERVER_ONLY -eq 1 ]; then
  echo "서버만 실행 모드. Ctrl+C를 눌러 종료하세요..."
  # 서버 로그 실시간 표시
  tail -f "$SERVER_LOG"
  # 사용자가 Ctrl+C로 종료하면 trap 함수가 실행됨
  exit 0
fi

# 클라이언트 실행 (서버만 실행 모드가 아닌 경우)
if [ $SERVER_ONLY -eq 0 ]; then
  echo "클라이언트 시작 중..."

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
  echo "클라이언트 종료됨 (종료 코드: $CLIENT_EXIT_CODE)"
fi

echo "===== LLM MCP 테스트 완료 ====="
echo "로그 파일:"
echo "- 서버 로그: $SERVER_LOG"
echo "- 클라이언트 로그: $CLIENT_LOG"

exit ${CLIENT_EXIT_CODE:-0}