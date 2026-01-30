import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import '../../../lib/auth_middleware.dart';

Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  if (method == HttpMethod.get) {
    return _getMe(context);
  }
  if (method == HttpMethod.patch) {
    return _patchMe(context);
  }
  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _getMe(RequestContext context) async {
  final userId = getUserId(context);
  final pool = context.read<Pool>();
  await _ensureUserProfileColumns(pool);

  try {
    final result = await pool.execute(
      Sql.named('''
        SELECT id, username, email, display_name, avatar_url, created_at, updated_at
        FROM users
        WHERE id = @id
        LIMIT 1
      '''),
      parameters: {'id': userId},
    );

    if (result.isEmpty) {
      return Response.json(statusCode: HttpStatus.notFound, body: {'error': 'Usuário não encontrado'});
    }

    final map = result.first.toColumnMap();
    return Response.json(
      body: {
        'user': {
          'id': map['id'],
          'username': map['username'],
          'email': map['email'],
          'display_name': map['display_name'],
          'avatar_url': map['avatar_url'],
          'created_at': (map['created_at'] as DateTime?)?.toIso8601String(),
          'updated_at': (map['updated_at'] as DateTime?)?.toIso8601String(),
        },
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Falha ao buscar perfil', 'details': e.toString()},
    );
  }
}

Future<Response> _patchMe(RequestContext context) async {
  final userId = getUserId(context);
  final pool = context.read<Pool>();
  await _ensureUserProfileColumns(pool);

  Map<String, dynamic> body;
  try {
    body = await context.request.json() as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: HttpStatus.badRequest, body: {'error': 'JSON inválido'});
  }

  final updateFields = <String>[];
  final params = <String, dynamic>{'id': userId};

  if (body.containsKey('display_name')) {
    final raw = body['display_name'];
    final value = raw == null ? null : raw.toString().trim();
    if (value != null && value.length > 50) {
      return Response.json(statusCode: HttpStatus.badRequest, body: {'error': 'display_name muito longo (max 50)'});
    }
    updateFields.add('display_name = @display_name');
    params['display_name'] = (value == null || value.isEmpty) ? null : value;
  }

  if (body.containsKey('avatar_url')) {
    final raw = body['avatar_url'];
    final value = raw == null ? null : raw.toString().trim();
    if (value != null && value.isNotEmpty) {
      final uri = Uri.tryParse(value);
      final isValid = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
      if (!isValid) {
        return Response.json(statusCode: HttpStatus.badRequest, body: {'error': 'avatar_url inválida (http/https)'});
      }
      if (value.length > 500) {
        return Response.json(statusCode: HttpStatus.badRequest, body: {'error': 'avatar_url muito longa (max 500)'});
      }
    }
    updateFields.add('avatar_url = @avatar_url');
    params['avatar_url'] = (value == null || value.isEmpty) ? null : value;
  }

  if (updateFields.isEmpty) {
    return Response.json(statusCode: HttpStatus.badRequest, body: {'error': 'Nada para atualizar'});
  }

  try {
    final result = await pool.execute(
      Sql.named('''
        UPDATE users
        SET ${updateFields.join(', ')},
            updated_at = CURRENT_TIMESTAMP
        WHERE id = @id
        RETURNING id, username, email, display_name, avatar_url, created_at, updated_at
      '''),
      parameters: params,
    );

    if (result.isEmpty) {
      return Response.json(statusCode: HttpStatus.notFound, body: {'error': 'Usuário não encontrado'});
    }

    final map = result.first.toColumnMap();
    return Response.json(
      body: {
        'user': {
          'id': map['id'],
          'username': map['username'],
          'email': map['email'],
          'display_name': map['display_name'],
          'avatar_url': map['avatar_url'],
          'created_at': (map['created_at'] as DateTime?)?.toIso8601String(),
          'updated_at': (map['updated_at'] as DateTime?)?.toIso8601String(),
        },
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Falha ao atualizar perfil', 'details': e.toString()},
    );
  }
}

Future<void> _ensureUserProfileColumns(Pool pool) async {
  // Idempotente e rápido; evita quebrar deploys onde o schema ainda não foi aplicado.
  await pool.execute(Sql.named('ALTER TABLE users ADD COLUMN IF NOT EXISTS display_name TEXT'));
  await pool.execute(Sql.named('ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT'));
  await pool.execute(
    Sql.named('ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP'),
  );
}
