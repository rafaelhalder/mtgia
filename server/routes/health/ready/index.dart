import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// GET /health/ready - Readiness check (verifica dependências)
/// 
/// Usado para verificar se o servidor está pronto para receber tráfego.
/// Verifica conexão com o banco de dados.
/// Retorna 200 OK se todas as dependências estão funcionando.
/// Retorna 503 Service Unavailable se alguma dependência falhar.
Future<Response> onRequest(RequestContext context) async {
  final checks = <String, dynamic>{};
  var allHealthy = true;

  // Check 1: Database connection
  try {
    final pool = context.read<Pool>();
    final result = await pool.execute('SELECT 1 as health_check').timeout(
      const Duration(seconds: 5),
    );
    
    if (result.isNotEmpty) {
      checks['database'] = {
        'status': 'healthy',
        'latency_ms': null, // Pode ser adicionado futuramente
      };
    } else {
      checks['database'] = {'status': 'unhealthy', 'error': 'Empty result'};
      allHealthy = false;
    }
  } catch (e) {
    print('[ERROR] handler: $e');
    checks['database'] = {'status': 'unhealthy', 'error': e.toString()};
    allHealthy = false;
  }

  // Check 2: Cards table has data
  try {
    final pool = context.read<Pool>();
    final result = await pool.execute(
      'SELECT COUNT(*)::int FROM cards LIMIT 1',
    ).timeout(const Duration(seconds: 5));
    
    final count = result.first[0] as int? ?? 0;
    checks['cards_data'] = {
      'status': count > 0 ? 'healthy' : 'warning',
      'card_count': count,
    };
    
    if (count == 0) {
      checks['cards_data']['message'] = 'No cards in database - run sync_cards';
    }
  } catch (e) {
    print('[ERROR] handler: $e');
    checks['cards_data'] = {'status': 'unhealthy', 'error': e.toString()};
    allHealthy = false;
  }

  final response = {
    'status': allHealthy ? 'ready' : 'not_ready',
    'service': 'mtgia-server',
    'timestamp': DateTime.now().toIso8601String(),
    'environment': Platform.environment['ENVIRONMENT'] ?? 'development',
    'checks': checks,
  };

  return Response.json(
    statusCode: allHealthy ? HttpStatus.ok : HttpStatus.serviceUnavailable,
    body: response,
  );
}
