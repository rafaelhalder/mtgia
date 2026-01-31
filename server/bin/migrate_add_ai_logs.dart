// ignore_for_file: avoid_print

import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

/// Migration: Adiciona tabela ai_logs para observabilidade das chamadas de IA
/// 
/// Esta tabela permite:
/// - Debugar recomendações da IA
/// - Medir latência das chamadas
/// - Analisar padrões de uso
/// - Auditar custos (tokens)
void main() async {
  final env = DotEnv()..load();

  final connection = await Connection.open(
    Endpoint(
      host: env['DB_HOST'] ?? 'localhost',
      database: env['DB_NAME'] ?? 'mtg_db',
      username: env['DB_USER'] ?? 'postgres',
      password: env['DB_PASS'] ?? 'postgres',
      port: int.parse(env['DB_PORT'] ?? '5432'),
    ),
    settings: ConnectionSettings(sslMode: SslMode.disable),
  );

  try {
    print('🔄 Criando tabela ai_logs...');

    await connection.execute('''
      CREATE TABLE IF NOT EXISTS ai_logs (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        
        -- Contexto da chamada
        user_id UUID REFERENCES users(id) ON DELETE SET NULL,
        deck_id UUID REFERENCES decks(id) ON DELETE SET NULL,
        endpoint TEXT NOT NULL,              -- 'optimize', 'generate', 'explain', 'archetypes'
        
        -- Request (sem expor secrets)
        model TEXT NOT NULL,                 -- 'gpt-4o', 'gpt-4o-mini', etc.
        prompt_summary TEXT,                 -- Resumo do prompt (sem dados sensíveis)
        input_tokens INTEGER,                -- Tokens de entrada (se disponível)
        
        -- Response
        output_tokens INTEGER,               -- Tokens de saída (se disponível)
        response_summary TEXT,               -- Resumo da resposta
        success BOOLEAN NOT NULL DEFAULT TRUE,
        error_message TEXT,                  -- Mensagem de erro (se falhou)
        
        -- Performance
        latency_ms INTEGER NOT NULL,         -- Tempo total da chamada em ms
        
        -- Metadata
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    print('✅ Tabela ai_logs criada');

    // Índices para consultas comuns
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_ai_logs_user ON ai_logs (user_id);
    ''');
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_ai_logs_deck ON ai_logs (deck_id);
    ''');
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_ai_logs_endpoint ON ai_logs (endpoint);
    ''');
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_ai_logs_created ON ai_logs (created_at DESC);
    ''');
    await connection.execute('''
      CREATE INDEX IF NOT EXISTS idx_ai_logs_success ON ai_logs (success);
    ''');

    print('✅ Índices criados');

    // Adicionar ao database_setup.sql (documentação)
    print('''
    
📝 Adicione ao database_setup.sql:

-- 14. Tabela de Logs de IA (Observabilidade)
-- Armazena métricas e resumos das chamadas de IA para debugging e auditoria
CREATE TABLE IF NOT EXISTS ai_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    deck_id UUID REFERENCES decks(id) ON DELETE SET NULL,
    endpoint TEXT NOT NULL,
    model TEXT NOT NULL,
    prompt_summary TEXT,
    input_tokens INTEGER,
    output_tokens INTEGER,
    response_summary TEXT,
    success BOOLEAN NOT NULL DEFAULT TRUE,
    error_message TEXT,
    latency_ms INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ai_logs_user ON ai_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_ai_logs_deck ON ai_logs (deck_id);
CREATE INDEX IF NOT EXISTS idx_ai_logs_endpoint ON ai_logs (endpoint);
CREATE INDEX IF NOT EXISTS idx_ai_logs_created ON ai_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_logs_success ON ai_logs (success);
    ''');

    print('✅ Migração concluída com sucesso!');
  } catch (e) {
    print('❌ Erro na migração: $e');
    exit(1);
  } finally {
    await connection.close();
  }
}
