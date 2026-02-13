import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../../lib/auth_middleware.dart';

/// PUT /users/me/fcm-token
/// Salva ou atualiza o FCM token do usuário logado.
///
/// Body: { "token": "fcm_token_string" }
///
/// DELETE /users/me/fcm-token
/// Remove o FCM token (logout / desabilitar push).
Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  if (method == HttpMethod.put) return _putToken(context);
  if (method == HttpMethod.delete) return _deleteToken(context);
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _putToken(RequestContext context) async {
  final userId = getUserId(context);
  final pool = context.read<Pool>();

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'JSON inválido'},
    );
  }

  final token = (body['token'] as String?)?.trim();
  if (token == null || token.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'token é obrigatório'},
    );
  }

  if (token.length > 500) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'token muito longo'},
    );
  }

  try {
    await pool.execute(
      Sql.named('''
        UPDATE users SET fcm_token = @token, updated_at = CURRENT_TIMESTAMP
        WHERE id = @id
      '''),
      parameters: {'id': userId, 'token': token},
    );

    return Response.json(body: {'ok': true});
  } catch (e) {
    print('[ERROR] PUT /users/me/fcm-token: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Falha ao salvar token'},
    );
  }
}

Future<Response> _deleteToken(RequestContext context) async {
  final userId = getUserId(context);
  final pool = context.read<Pool>();

  try {
    await pool.execute(
      Sql.named('''
        UPDATE users SET fcm_token = NULL, updated_at = CURRENT_TIMESTAMP
        WHERE id = @id
      '''),
      parameters: {'id': userId},
    );

    return Response.json(body: {'ok': true});
  } catch (e) {
    print('[ERROR] DELETE /users/me/fcm-token: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Falha ao remover token'},
    );
  }
}
