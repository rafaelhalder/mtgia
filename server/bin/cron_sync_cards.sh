#!/usr/bin/env bash
set -euo pipefail

# Script para rodar no Droplet via cron:
# - Descobre o container atual do Easypanel (evita nome hardcoded)
# - Executa o sync incremental de cartas
# - Registra logs e tempos de execução
#
# Variáveis opcionais:
# - CONTAINER_PATTERN (default: ^evolution_cartinhas\\.)
# - CONTAINER_LABEL (alternativa ao pattern, ex: com.docker.compose.service=mtgia)
# - WORKDIR (default: /app)
# - DART_ARGS (default: bin/sync_cards.dart)
# - LOG_FILE (opcional, arquivo para append de logs)

CONTAINER_PATTERN="${CONTAINER_PATTERN:-^evolution_cartinhas\\.}"
CONTAINER_LABEL="${CONTAINER_LABEL:-}"
WORKDIR="${WORKDIR:-/app}"
DART_ARGS="${DART_ARGS:-bin/sync_cards.dart}"
LOG_FILE="${LOG_FILE:-}"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg"
  if [[ -n "${LOG_FILE}" ]]; then
    echo "$msg" >> "${LOG_FILE}"
  fi
}

# Encontra container por label ou pattern
find_container() {
  local container_name=""
  
  # Primeiro tenta por label (mais confiável)
  if [[ -n "${CONTAINER_LABEL}" ]]; then
    container_name="$(docker ps --filter "label=${CONTAINER_LABEL}" --format '{{.Names}}' | head -n 1 || true)"
  fi
  
  # Se não encontrou por label, tenta por pattern
  if [[ -z "${container_name}" ]]; then
    container_name="$(docker ps --format '{{.Names}}' | grep -E "${CONTAINER_PATTERN}" | head -n 1 || true)"
  fi
  
  echo "${container_name}"
}

container_name="$(find_container)"

if [[ -z "${container_name}" ]]; then
  log "ERROR: nenhum container encontrado"
  log "  Pattern: ${CONTAINER_PATTERN}"
  log "  Label: ${CONTAINER_LABEL:-<não definido>}"
  log "Containers disponíveis:"
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' >&2
  exit 1
fi

log "Iniciando sync_cards no container: ${container_name}"
start_time=$(date +%s)

if docker exec -w "${WORKDIR}" "${container_name}" dart run ${DART_ARGS}; then
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  log "✅ Sync concluído com sucesso em ${duration}s"
else
  exit_code=$?
  log "❌ Sync falhou com código: ${exit_code}"
  exit ${exit_code}
fi

