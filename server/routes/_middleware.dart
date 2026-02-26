import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import '../lib/database.dart';

// Instancia o banco de dados uma vez.
final _db = Database();
var _connected = false;

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Max-Age': '86400',
};

Handler middleware(Handler handler) {
  return (context) async {
    // ── CORS preflight ───────────────────────────────────
    if (context.request.method == HttpMethod.options) {
      return Response(statusCode: HttpStatus.noContent, headers: _corsHeaders);
    }

    try {
      // ── DB ────────────────────────────────────────────────
      if (!_connected) {
        await _db.connect();
        if (!_db.isConnected) {
          return Response.json(
            statusCode: HttpStatus.serviceUnavailable,
            body: {'error': 'Serviço temporariamente indisponível (DB)'},
            headers: _corsHeaders,
          );
        }
        _connected = true;
      }

      // Executa o handler com Pool injetado.
      final response =
          await handler.use(provider<Pool>((_) => _db.connection))(context);

      // ── Adiciona CORS nas respostas ──────────────────────
      // Evita materializar o body (performance/streaming).
      final merged = <String, Object>{...response.headers, ..._corsHeaders};
      return response.copyWith(headers: merged);
    } catch (e, st) {
      print('[ERROR] middleware: $e');
      print('[ERROR] stack: $st');
      return Response.json(
        statusCode: HttpStatus.internalServerError,
        body: {'error': 'Erro interno do servidor'},
        headers: _corsHeaders,
      );
    }
  };
}
