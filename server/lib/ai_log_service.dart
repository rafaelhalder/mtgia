import 'package:postgres/postgres.dart';

/// Serviço para logging de chamadas de IA
/// 
/// Permite observabilidade das chamadas sem expor dados sensíveis.
/// Útil para debugging, auditoria de custos e análise de performance.
class AiLogService {
  final Connection _db;

  AiLogService(this._db);

  /// Registra uma chamada de IA
  /// 
  /// [userId] - ID do usuário que fez a chamada (opcional)
  /// [deckId] - ID do deck relacionado (opcional)
  /// [endpoint] - Nome do endpoint ('optimize', 'generate', etc.)
  /// [model] - Modelo usado ('gpt-4o', 'gpt-4o-mini')
  /// [promptSummary] - Resumo do prompt (SEM dados sensíveis)
  /// [responseSummary] - Resumo da resposta
  /// [latencyMs] - Tempo da chamada em milissegundos
  /// [inputTokens] - Tokens de entrada (opcional)
  /// [outputTokens] - Tokens de saída (opcional)
  /// [success] - Se a chamada foi bem sucedida
  /// [errorMessage] - Mensagem de erro (se falhou)
  Future<void> log({
    String? userId,
    String? deckId,
    required String endpoint,
    required String model,
    String? promptSummary,
    String? responseSummary,
    required int latencyMs,
    int? inputTokens,
    int? outputTokens,
    bool success = true,
    String? errorMessage,
  }) async {
    try {
      await _db.execute(
        Sql.named('''
          INSERT INTO ai_logs (
            user_id, deck_id, endpoint, model, 
            prompt_summary, response_summary, 
            latency_ms, input_tokens, output_tokens,
            success, error_message
          ) VALUES (
            @userId::uuid, @deckId::uuid, @endpoint, @model,
            @promptSummary, @responseSummary,
            @latencyMs, @inputTokens, @outputTokens,
            @success, @errorMessage
          )
        '''),
        parameters: {
          'userId': userId,
          'deckId': deckId,
          'endpoint': endpoint,
          'model': model,
          'promptSummary': _truncate(promptSummary, 500),
          'responseSummary': _truncate(responseSummary, 500),
          'latencyMs': latencyMs,
          'inputTokens': inputTokens,
          'outputTokens': outputTokens,
          'success': success,
          'errorMessage': errorMessage,
        },
      );
    } catch (e) {
      // Não falhar a operação principal se o logging falhar
      print('⚠️ Falha ao salvar log de IA: $e');
    }
  }

  /// Helper para medir tempo de execução e logar automaticamente
  Future<T> loggedCall<T>({
    String? userId,
    String? deckId,
    required String endpoint,
    required String model,
    String? promptSummary,
    required Future<T> Function() call,
    String Function(T result)? summarizeResponse,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final result = await call();
      stopwatch.stop();
      
      await log(
        userId: userId,
        deckId: deckId,
        endpoint: endpoint,
        model: model,
        promptSummary: promptSummary,
        responseSummary: summarizeResponse?.call(result),
        latencyMs: stopwatch.elapsedMilliseconds,
        success: true,
      );
      
      return result;
    } catch (e) {
      stopwatch.stop();
      
      await log(
        userId: userId,
        deckId: deckId,
        endpoint: endpoint,
        model: model,
        promptSummary: promptSummary,
        latencyMs: stopwatch.elapsedMilliseconds,
        success: false,
        errorMessage: e.toString(),
      );
      
      rethrow;
    }
  }

  /// Busca logs recentes (para debugging)
  Future<List<Map<String, dynamic>>> getRecentLogs({
    String? userId,
    String? deckId,
    String? endpoint,
    int limit = 50,
  }) async {
    final where = <String>[];
    final params = <String, dynamic>{'limit': limit};

    if (userId != null) {
      where.add('user_id = @userId::uuid');
      params['userId'] = userId;
    }
    if (deckId != null) {
      where.add('deck_id = @deckId::uuid');
      params['deckId'] = deckId;
    }
    if (endpoint != null) {
      where.add('endpoint = @endpoint');
      params['endpoint'] = endpoint;
    }

    final whereClause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final result = await _db.execute(
      Sql.named('''
        SELECT 
          id, user_id, deck_id, endpoint, model,
          prompt_summary, response_summary,
          latency_ms, input_tokens, output_tokens,
          success, error_message, created_at
        FROM ai_logs
        $whereClause
        ORDER BY created_at DESC
        LIMIT @limit
      '''),
      parameters: params,
    );

    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Estatísticas de uso
  Future<Map<String, dynamic>> getStats({
    DateTime? since,
  }) async {
    final sinceClause = since != null 
        ? "WHERE created_at >= @since" 
        : "";
    
    final result = await _db.execute(
      Sql.named('''
        SELECT 
          COUNT(*) as total_calls,
          COUNT(*) FILTER (WHERE success = true) as successful_calls,
          COUNT(*) FILTER (WHERE success = false) as failed_calls,
          AVG(latency_ms)::int as avg_latency_ms,
          MAX(latency_ms) as max_latency_ms,
          MIN(latency_ms) as min_latency_ms,
          SUM(COALESCE(input_tokens, 0)) as total_input_tokens,
          SUM(COALESCE(output_tokens, 0)) as total_output_tokens
        FROM ai_logs
        $sinceClause
      '''),
      parameters: since != null ? {'since': since.toIso8601String()} : {},
    );

    if (result.isEmpty) {
      return {
        'total_calls': 0,
        'successful_calls': 0,
        'failed_calls': 0,
        'avg_latency_ms': 0,
        'max_latency_ms': 0,
        'min_latency_ms': 0,
        'total_input_tokens': 0,
        'total_output_tokens': 0,
      };
    }

    return result.first.toColumnMap();
  }

  /// Estatísticas por endpoint
  Future<List<Map<String, dynamic>>> getStatsByEndpoint({
    DateTime? since,
  }) async {
    final sinceClause = since != null 
        ? "WHERE created_at >= @since" 
        : "";
    
    final result = await _db.execute(
      Sql.named('''
        SELECT 
          endpoint,
          COUNT(*) as total_calls,
          COUNT(*) FILTER (WHERE success = true) as successful_calls,
          AVG(latency_ms)::int as avg_latency_ms
        FROM ai_logs
        $sinceClause
        GROUP BY endpoint
        ORDER BY total_calls DESC
      '''),
      parameters: since != null ? {'since': since.toIso8601String()} : {},
    );

    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Trunca string para evitar logs muito grandes
  String? _truncate(String? text, int maxLength) {
    if (text == null) return null;
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }
}
