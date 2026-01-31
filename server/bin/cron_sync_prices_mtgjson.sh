#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Cron para atualização diária de preços via MTGJSON
# ============================================================
#
# Este script usa o sync otimizado que:
# 1. Baixa AllPricesToday.json + AllIdentifiers.json (com cache)
# 2. Insere em tabela temporária no banco
# 3. UPDATE com JOIN (rápido!)
#
# CONFIGURAÇÃO NO CRONTAB:
# -------------------------
# Edite com: crontab -e
#
# Rodar todo dia às 4:00 AM:
#   0 4 * * * /path/to/server/bin/cron_sync_prices_mtgjson.sh >> /var/log/mtg_prices.log 2>&1
#
# Rodar de 12 em 12 horas:
#   0 */12 * * * /path/to/server/bin/cron_sync_prices_mtgjson.sh >> /var/log/mtg_prices.log 2>&1
#
# WINDOWS (Task Scheduler):
# -------------------------
# 1. Abra "Task Scheduler"
# 2. Create Basic Task...
# 3. Trigger: Daily, 04:00
# 4. Action: Start a program
#    Program: powershell.exe
#    Arguments: -ExecutionPolicy Bypass -File "C:\path\to\cron_sync_prices_mtgjson.ps1"
#
# DOCKER:
# -------
#   docker exec -t -w /app <container> dart run bin/sync_prices_mtgjson_fast.dart
#
# ============================================================

APP_DIR="${APP_DIR:-$(dirname "$0")/..}"
cd "$APP_DIR"

echo "============================================================"
echo "🕐 $(date '+%Y-%m-%d %H:%M:%S') - Iniciando sync de preços MTGJSON"
echo "============================================================"

# Usa cache existente (não força re-download)
# Para forçar: adicione --force-download
dart run bin/sync_prices_mtgjson_fast.dart

echo "✅ $(date '+%Y-%m-%d %H:%M:%S') - Sync concluído"
echo ""
