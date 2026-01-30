#!/usr/bin/env bash
set -euo pipefail

# Script para rodar no Droplet via cron:
# - Descobre o container atual do Easypanel (evita nome hardcoded)
# - Executa o sync incremental de cartas
#
# Variáveis opcionais:
# - CONTAINER_PATTERN (default: ^evolution_cartinhas\\.)
# - WORKDIR (default: /app)
# - DART_ARGS (default: bin/sync_cards.dart)

CONTAINER_PATTERN="${CONTAINER_PATTERN:-^evolution_cartinhas\\.}"
WORKDIR="${WORKDIR:-/app}"
DART_ARGS="${DART_ARGS:-bin/sync_cards.dart}"

container_name="$(docker ps --format '{{.Names}}' | grep -E "${CONTAINER_PATTERN}" | head -n 1 || true)"

if [[ -z "${container_name}" ]]; then
  echo "ERROR: nenhum container encontrado com pattern: ${CONTAINER_PATTERN}" >&2
  docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' >&2
  exit 1
fi

echo "Running sync_cards on container: ${container_name}"
docker exec -w "${WORKDIR}" "${container_name}" dart run ${DART_ARGS}

