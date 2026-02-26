#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
API_BASE_URL_WAS_SET=0
if [[ -n "${API_BASE_URL:-}" ]]; then
  API_BASE_URL_WAS_SET=1
fi

PORT="${PORT:-8080}"
API_BASE_URL="${API_BASE_URL:-http://localhost:${PORT}}"
SERVER_START_TIMEOUT="${SERVER_START_TIMEOUT:-45}"

SERVER_PID=""
STARTED_BY_SCRIPT=0

print_header() {
  echo ""
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

api_ready() {
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  local headers_file body_file
  headers_file="$(mktemp)"
  body_file="$(mktemp)"

  cleanup_probe_files() {
    rm -f "$headers_file" "$body_file"
  }

  local probe_url="${API_BASE_URL%/}/health/ready"
  curl -sS -m 5 -D "$headers_file" -o "$body_file" "$probe_url" >/dev/null 2>&1 || true

  if [[ ! -s "$headers_file" ]]; then
    probe_url="${API_BASE_URL%/}/auth/login"
    curl -sS -m 5 -D "$headers_file" -o "$body_file" -X POST "$probe_url" -H 'Content-Type: application/json' -d '{}' >/dev/null 2>&1 || true
    [[ -s "$headers_file" ]] || {
      cleanup_probe_files
      return 1
    }
  fi

  local content_type status body
  content_type="$(awk -F': ' 'tolower($1)=="content-type"{print tolower($2)}' "$headers_file" | tr -d '\r' | tail -n1)"
  status="$(awk 'toupper($1) ~ /^HTTP\// {code=$2} END{print code}' "$headers_file")"
  body="$(cat "$body_file")"

  cleanup_probe_files

  [[ "$status" =~ ^(200|400|401|403|405|503)$ ]] || return 1
  [[ "$content_type" == application/json* ]] || return 1
  [[ "$body" == *"status"* || "$body" == *"error"* || "$body" == *"token"* || "$body" == *"user"* || "$body" == *"message"* ]] || return 1

  return 0
}

port_in_use() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN -t >/dev/null 2>&1
    return
  fi

  if command -v nc >/dev/null 2>&1; then
    nc -z localhost "$port" >/dev/null 2>&1
    return
  fi

  return 1
}

select_free_local_port() {
  local from_port="$1"
  local max_tries="${2:-20}"
  local p

  for ((offset = 0; offset <= max_tries; offset++)); do
    p=$((from_port + offset))
    if ! port_in_use "$p"; then
      echo "$p"
      return 0
    fi
  done

  return 1
}

cleanup() {
  if [[ "$STARTED_BY_SCRIPT" -eq 1 && -n "$SERVER_PID" ]]; then
    if kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      print_header "Encerrando API local"
      kill "$SERVER_PID" >/dev/null 2>&1 || true
      wait "$SERVER_PID" 2>/dev/null || true
    fi
  fi
}

trap cleanup EXIT INT TERM

print_header "Preparando integração local"
echo "API_BASE_URL=${API_BASE_URL}"

if api_ready; then
  echo "ℹ️ API já está pronta em ${API_BASE_URL}."
else
  if [[ "$API_BASE_URL_WAS_SET" -eq 0 && "$API_BASE_URL" == http://localhost:* ]]; then
    if port_in_use "$PORT"; then
      next_port="$(select_free_local_port "$PORT" 30 || true)"
      if [[ -n "$next_port" ]]; then
        PORT="$next_port"
        API_BASE_URL="http://[::1]:${PORT}"
        echo "ℹ️ Porta 8080 ocupada por outro serviço. Usando porta local livre: ${PORT}."
      fi
    fi
  fi

  if [[ ! -f "$ROOT_DIR/server/build/bin/server.dart" || "${FORCE_BUILD:-0}" == "1" ]]; then
    echo "ℹ️ Gerando build do Dart Frog para execução não-interativa..."
    (
      cd "$ROOT_DIR/server"
      dart_frog build
    ) >/tmp/mtgia_dart_frog_build.log 2>&1
  fi

  echo "ℹ️ API não detectada. Iniciando servidor compilado local em porta ${PORT}..."
  (
    cd "$ROOT_DIR/server"
    PORT="$PORT" dart run build/bin/server.dart
  ) >/tmp/mtgia_dart_frog_dev.log 2>&1 &

  SERVER_PID="$!"
  STARTED_BY_SCRIPT=1

  for ((i = 1; i <= SERVER_START_TIMEOUT; i++)); do
    if api_ready; then
      echo "✅ API pronta em ${API_BASE_URL} (t=${i}s)."
      break
    fi

    if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
      echo "❌ O processo do servidor encerrou antes de ficar pronto."
      echo "   Verifique logs em /tmp/mtgia_dart_frog_dev.log"
      exit 1
    fi

    sleep 1

    if [[ "$i" -eq "$SERVER_START_TIMEOUT" ]]; then
      echo "❌ Timeout aguardando API local em ${API_BASE_URL}."
      echo "   Verifique logs em /tmp/mtgia_dart_frog_dev.log"
      exit 1
    fi
  done
fi

print_header "Executando quality gate full"
API_BASE_URL="$API_BASE_URL" "$ROOT_DIR/scripts/quality_gate.sh" full

print_header "Fluxo completo finalizado"
echo "✅ Gate completo com integração local executado com sucesso."
