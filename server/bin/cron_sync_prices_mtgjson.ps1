# ============================================================
# Script PowerShell para atualização diária de preços (Windows)
# ============================================================
#
# COMO AGENDAR NO TASK SCHEDULER:
# 1. Abra "Task Scheduler" (taskschd.msc)
# 2. "Create Basic Task..."
# 3. Nome: "MTG Price Sync"
# 4. Trigger: Daily, 04:00 AM
# 5. Action: "Start a program"
#    - Program: powershell.exe
#    - Arguments: -ExecutionPolicy Bypass -File "C:\Users\rafae\Documents\project\mtgia\server\bin\cron_sync_prices_mtgjson.ps1"
#    - Start in: C:\Users\rafae\Documents\project\mtgia\server
#
# PARA TESTAR MANUALMENTE:
#   .\bin\cron_sync_prices_mtgjson.ps1
#
# ============================================================

$ErrorActionPreference = "Stop"

# Diretório do servidor
$ServerDir = Split-Path -Parent $PSScriptRoot
Set-Location $ServerDir

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "============================================================"
Write-Host "🕐 $timestamp - Iniciando sync de preços MTGJSON"
Write-Host "============================================================"

# Executa o sync otimizado
# Remove --force-download se quiser usar cache (mais rápido)
dart run bin/sync_prices_mtgjson_fast.dart

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "✅ $timestamp - Sync concluído"
Write-Host ""
