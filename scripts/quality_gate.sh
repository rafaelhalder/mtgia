#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-quick}"
API_BASE_URL="${API_BASE_URL:-http://localhost:8080}"

print_header() {
  echo ""
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

run_backend_quick() {
  print_header "Backend quick checks"
  cd "$ROOT_DIR/server"
  dart test
}

run_backend_full() {
  print_header "Backend full checks"
  cd "$ROOT_DIR/server"

  if _is_backend_api_ready; then
    echo "ℹ️ API detectada em ${API_BASE_URL} — habilitando testes de integração backend."
    RUN_INTEGRATION_TESTS=1 TEST_API_BASE_URL="$API_BASE_URL" dart test -j 1
  else
    echo "⚠️ API não detectada (ou resposta não-JSON esperada) em ${API_BASE_URL}."
    echo "   Rodando suíte backend sem integração."
    echo "   Dica: inicie 'cd server && dart_frog dev' ou exporte API_BASE_URL para sua URL do Easypanel."
    dart test
  fi
}

_is_backend_api_ready() {
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

run_frontend_quick() {
  print_header "Frontend quick checks"
  cd "$ROOT_DIR/app"
  flutter analyze --no-fatal-infos
}

run_frontend_full() {
  print_header "Frontend full checks"
  cd "$ROOT_DIR/app"
  flutter analyze --no-fatal-infos
  flutter test
}

ensure_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Comando não encontrado: $1"
    exit 1
  fi
}

ensure_prerequisites() {
  ensure_cmd dart
  ensure_cmd flutter
}

print_usage() {
  cat <<EOF
Uso:
  ./scripts/quality_gate.sh quick   # validação rápida (dart test + flutter analyze)
  ./scripts/quality_gate.sh full    # validação completa (dart test + flutter analyze + flutter test)

Dica:
  Use 'quick' durante implementação e 'full' antes de concluir item/sprint.
  No modo 'full', se a API responder corretamente em API_BASE_URL
  (default: http://localhost:8080), os testes de integração backend
  são habilitados automaticamente.

Exemplos:
  ./scripts/quality_gate.sh full
  API_BASE_URL=https://sua-api.easypanel.host ./scripts/quality_gate.sh full
EOF
}

main() {
  ensure_prerequisites

  case "$MODE" in
    quick)
      run_backend_quick
      run_frontend_quick
      ;;
    full)
      run_backend_full
      run_frontend_full
      ;;
    -h|--help|help)
      print_usage
      exit 0
      ;;
    *)
      echo "❌ Modo inválido: $MODE"
      print_usage
      exit 1
      ;;
  esac

  print_header "Quality gate concluído"
  echo "✅ Todos os checks do modo '$MODE' passaram."
}

main "$@"
