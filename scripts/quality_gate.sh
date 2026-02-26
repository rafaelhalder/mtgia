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
    RUN_INTEGRATION_TESTS=1 dart test
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

  local probe_url="${API_BASE_URL%/}/auth/login"
  local output

  output="$(curl -sS -m 5 -D - -X POST "$probe_url" -H 'Content-Type: application/json' -d '{}' || true)"

  if [[ -z "$output" ]]; then
    return 1
  fi

  local headers body content_type status
  headers="${output%%$'\r\n\r\n'*}"
  body="${output#*$'\r\n\r\n'}"
  content_type="$(printf '%s\n' "$headers" | awk -F': ' 'BEGIN{IGNORECASE=1} /^Content-Type:/{print tolower($2)}' | tr -d '\r' | tail -n1)"
  status="$(printf '%s\n' "$headers" | awk 'NR==1{print $2}')"

  [[ "$status" =~ ^(200|400|401|403|405)$ ]] || return 1
  [[ "$content_type" == application/json* ]] || return 1
  [[ "$body" == *"error"* || "$body" == *"token"* || "$body" == *"user"* ]] || return 1

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
