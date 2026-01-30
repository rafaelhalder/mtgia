#!/usr/bin/env bash
set -euo pipefail

# Cron helper para atualizar preços via Scryfall.
# Requisitos:
# - Rodar dentro do container (ou host com Dart instalado).
# - Variáveis DB_* disponíveis (ou .env carregado pelo ambiente).
#
# Exemplo (host):
#   docker exec -t -w /app <container> dart run bin/sync_prices.dart --limit=2000 --stale-hours=24

APP_DIR="${APP_DIR:-/app}"
cd "$APP_DIR"

dart run bin/sync_prices.dart --limit="${SYNC_PRICES_LIMIT:-2000}" --stale-hours="${SYNC_PRICES_STALE_HOURS:-24}"

