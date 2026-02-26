#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-quick}"

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

  if command -v curl >/dev/null 2>&1 && curl -sSf "http://localhost:8080/" >/dev/null 2>&1; then
    echo "ℹ️ API detectada em http://localhost:8080 — habilitando testes de integração backend."
    RUN_INTEGRATION_TESTS=1 dart test
  else
    echo "⚠️ API local não detectada em http://localhost:8080."
    echo "   Rodando suíte backend sem integração (inicie 'cd server && dart_frog dev' para incluir integração)."
    dart test
  fi
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
  No modo 'full', se a API local estiver ativa em http://localhost:8080,
  os testes de integração backend são habilitados automaticamente.
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
