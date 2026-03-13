#!/usr/bin/env python3
"""
Auditoria de Schema vs Código
Compara colunas do PostgreSQL com referências no código Dart.
"""

import psycopg2
import os
import re
import json
from pathlib import Path
from collections import defaultdict

# Configuração
DB_URL = "postgresql://postgres:c2abeef5e66f21b0ce86@143.198.230.247:5433/halder"
SERVER_DIR = Path(__file__).parent.parent
ROUTES_DIR = SERVER_DIR / "routes"
LIB_DIR = SERVER_DIR / "lib"


def get_db_schema():
    """Extrai schema completo do PostgreSQL."""
    conn = psycopg2.connect(DB_URL)
    cur = conn.cursor()
    
    # Todas as tabelas e colunas
    cur.execute("""
        SELECT 
            t.table_name,
            c.column_name,
            c.data_type,
            c.is_nullable,
            c.column_default
        FROM information_schema.tables t
        JOIN information_schema.columns c 
            ON t.table_name = c.table_name
        WHERE t.table_schema = 'public'
            AND t.table_type = 'BASE TABLE'
        ORDER BY t.table_name, c.ordinal_position
    """)
    
    schema = defaultdict(list)
    for row in cur.fetchall():
        table_name, col_name, data_type, is_nullable, default = row
        schema[table_name].append({
            "column": col_name,
            "type": data_type,
            "nullable": is_nullable == "YES",
            "default": default
        })
    
    conn.close()
    return dict(schema)


def find_column_references_in_code():
    """Busca referências a colunas no código Dart."""
    references = defaultdict(set)
    
    # Padrões para detectar referências a colunas
    patterns = [
        # row['column_name'] ou row["column_name"]
        r"row\[['\"](\w+)['\"]\]",
        # data['column_name']
        r"data\[['\"](\w+)['\"]\]",
        # result['column_name']
        r"result\[['\"](\w+)['\"]\]",
        # INSERT INTO table (col1, col2)
        r"INSERT\s+INTO\s+(\w+)\s*\(([^)]+)\)",
        # UPDATE table SET col1 =
        r"UPDATE\s+(\w+)\s+SET\s+([^W]+?)(?:\s+WHERE|$)",
        # SELECT col1, col2 FROM table
        r"SELECT\s+(.+?)\s+FROM\s+(\w+)",
        # WHERE col = ou AND col =
        r"(?:WHERE|AND|OR)\s+(\w+)\s*[=<>!]",
        # ORDER BY col
        r"ORDER\s+BY\s+(\w+)",
        # GROUP BY col
        r"GROUP\s+BY\s+(\w+)",
        # table.column
        r"(\w+)\.(\w+)\s*[=<>!,)]",
        # 'column_name': value em Maps
        r"['\"](\w+)['\"]\s*:\s*",
        # AS alias
        r"AS\s+(\w+)",
    ]
    
    # Colunas conhecidas por tabela (para ajudar a mapear)
    table_column_hints = {
        "id": ["users", "cards", "decks", "deck_cards", "notifications", "conversations", "direct_messages", "trade_offers", "trade_items", "trade_messages", "user_binder_items"],
        "user_id": ["decks", "deck_cards", "notifications", "user_binder_items", "trade_offers", "conversations"],
        "deck_id": ["deck_cards", "deck_matchups", "battle_simulations", "ai_optimize_cache"],
        "card_id": ["deck_cards", "card_legalities", "user_binder_items", "trade_items"],
        "name": ["users", "cards", "decks", "rules"],
        "email": ["users"],
        "password_hash": ["users"],
        "username": ["users"],
    }
    
    all_columns = set()
    file_references = defaultdict(lambda: defaultdict(set))
    
    # Procurar em todos os arquivos .dart
    for dart_file in list(ROUTES_DIR.rglob("*.dart")) + list(LIB_DIR.rglob("*.dart")):
        try:
            content = dart_file.read_text()
            rel_path = str(dart_file.relative_to(SERVER_DIR))
            
            # Buscar todas as referências
            for pattern in patterns:
                for match in re.finditer(pattern, content, re.IGNORECASE | re.DOTALL):
                    groups = match.groups()
                    for g in groups:
                        if g:
                            # Limpar e separar colunas
                            cols = re.split(r'[,\s]+', g)
                            for col in cols:
                                col = col.strip().lower()
                                # Remover prefixos de tabela
                                if '.' in col:
                                    col = col.split('.')[-1]
                                # Filtrar palavras reservadas e muito curtas
                                if col and len(col) > 1 and col not in {
                                    'select', 'from', 'where', 'and', 'or', 'not', 'null',
                                    'true', 'false', 'as', 'on', 'in', 'is', 'like', 'between',
                                    'join', 'left', 'right', 'inner', 'outer', 'insert', 'into',
                                    'update', 'delete', 'set', 'values', 'order', 'by', 'group',
                                    'having', 'limit', 'offset', 'distinct', 'all', 'case', 'when',
                                    'then', 'else', 'end', 'cast', 'coalesce', 'count', 'sum',
                                    'avg', 'max', 'min', 'now', 'current_timestamp', 'lower',
                                    'upper', 'trim', 'substring', 'concat', 'length', 'to',
                                    'data', 'row', 'result', 'table', 'column', 'index', 'key',
                                    'value', 'the', 'new', 'old', 'begin', 'commit', 'rollback',
                                    'for', 'interval', 'day', 'days', 'hour', 'hours', 'jsonb',
                                    'text', 'varchar', 'integer', 'boolean', 'uuid', 'timestamp',
                                    'timestamptz', 'numeric', 'float', 'double', 'array', 'json',
                                }:
                                    all_columns.add(col)
                                    file_references[rel_path][col].add(match.group(0)[:50])
        except Exception as e:
            print(f"Erro lendo {dart_file}: {e}")
    
    return all_columns, dict(file_references)


def analyze_divergences(db_schema, code_columns, file_refs):
    """Analisa divergências entre schema e código."""
    
    # Todas as colunas do banco
    db_columns = set()
    db_columns_by_table = {}
    for table, cols in db_schema.items():
        db_columns_by_table[table] = {c["column"] for c in cols}
        for c in cols:
            db_columns.add(c["column"])
    
    # Colunas no código mas não no banco
    code_only = code_columns - db_columns
    
    # Colunas no banco mas não referenciadas no código
    db_only = db_columns - code_columns
    
    # Análise por tabela
    table_analysis = {}
    for table, cols in db_schema.items():
        col_names = {c["column"] for c in cols}
        used = col_names & code_columns
        unused = col_names - code_columns
        table_analysis[table] = {
            "total_columns": len(cols),
            "used_in_code": len(used),
            "unused_columns": sorted(unused),
            "columns": cols
        }
    
    return {
        "db_columns_total": len(db_columns),
        "code_columns_total": len(code_columns),
        "columns_in_code_not_in_db": sorted(code_only),
        "columns_in_db_not_in_code": sorted(db_only),
        "table_analysis": table_analysis
    }


def generate_report(db_schema, analysis, file_refs):
    """Gera relatório detalhado."""
    
    print("=" * 80)
    print("AUDITORIA DE SCHEMA vs CÓDIGO")
    print("=" * 80)
    
    print(f"\n📊 RESUMO GERAL")
    print(f"   Tabelas no banco: {len(db_schema)}")
    print(f"   Colunas no banco: {analysis['db_columns_total']}")
    print(f"   Referências no código: {analysis['code_columns_total']}")
    
    # Colunas no código que não existem no banco (CRÍTICO)
    if analysis["columns_in_code_not_in_db"]:
        print(f"\n🔴 COLUNAS REFERENCIADAS NO CÓDIGO MAS NÃO EXISTEM NO BANCO ({len(analysis['columns_in_code_not_in_db'])}):")
        for col in analysis["columns_in_code_not_in_db"][:30]:
            # Encontrar onde é referenciada
            files = []
            for f, refs in file_refs.items():
                if col in refs:
                    files.append(f)
            print(f"   - {col}")
            for f in files[:2]:
                print(f"     ↳ {f}")
    
    # Colunas não usadas por tabela
    print(f"\n⚠️  COLUNAS NO BANCO NÃO REFERENCIADAS NO CÓDIGO:")
    for table, info in sorted(analysis["table_analysis"].items()):
        unused = info["unused_columns"]
        if unused:
            pct = (len(unused) / info["total_columns"]) * 100
            print(f"\n   {table} ({len(unused)}/{info['total_columns']} não usadas - {pct:.0f}%):")
            for col in unused[:10]:
                col_info = next((c for c in info["columns"] if c["column"] == col), None)
                if col_info:
                    print(f"      - {col} ({col_info['type']})")
            if len(unused) > 10:
                print(f"      ... e mais {len(unused) - 10}")
    
    # Tabelas com 100% uso
    print(f"\n✅ TABELAS COM TODAS AS COLUNAS USADAS:")
    for table, info in sorted(analysis["table_analysis"].items()):
        if not info["unused_columns"]:
            print(f"   - {table} ({info['total_columns']} colunas)")
    
    # Salvar JSON detalhado
    output_file = SERVER_DIR / "test" / "artifacts" / "schema_audit_report.json"
    output_file.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_file, "w") as f:
        json.dump({
            "summary": {
                "tables": len(db_schema),
                "db_columns": analysis["db_columns_total"],
                "code_references": analysis["code_columns_total"],
                "potentially_missing": len(analysis["columns_in_code_not_in_db"]),
                "potentially_unused": len(analysis["columns_in_db_not_in_code"]),
            },
            "columns_in_code_not_in_db": analysis["columns_in_code_not_in_db"],
            "table_analysis": {
                table: {
                    "unused": info["unused_columns"],
                    "total": info["total_columns"]
                }
                for table, info in analysis["table_analysis"].items()
            },
            "db_schema": {
                table: [c["column"] for c in cols]
                for table, cols in db_schema.items()
            }
        }, f, indent=2)
    
    print(f"\n📁 Relatório detalhado salvo em: {output_file}")
    
    return output_file


def main():
    print("🔍 Coletando schema do PostgreSQL...")
    db_schema = get_db_schema()
    
    print(f"🔍 Buscando referências no código Dart...")
    code_columns, file_refs = find_column_references_in_code()
    
    print("🔍 Analisando divergências...")
    analysis = analyze_divergences(db_schema, code_columns, file_refs)
    
    generate_report(db_schema, analysis, file_refs)
    
    print("\n" + "=" * 80)
    print("AUDITORIA CONCLUÍDA")
    print("=" * 80)


if __name__ == "__main__":
    main()
