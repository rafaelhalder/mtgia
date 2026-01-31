#!/bin/bash
# Sync de preços MTG via MTGJSON - Roda diariamente no servidor

CONTAINER=$(docker ps --filter 'name=cartinhas' --format '{{.Names}}' | head -1)

if [ -z "$CONTAINER" ]; then
    echo "Container cartinhas não encontrado!"
    exit 1
fi

echo "[$(date)] Iniciando sync de preços no container $CONTAINER"

# Executa o sync dentro do container
docker exec $CONTAINER dart run bin/sync_prices_mtgjson_fast.dart 2>&1

echo "[$(date)] Sync concluído"
