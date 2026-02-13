import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import '../../lib/auth_service.dart';

/// Registro de novo usuário com gravação no banco de dados
/// 
/// POST /auth/register
/// Body: {"username": "joao", "email": "joao@example.com", "password": "senha123"}
/// 
/// Retorna:
/// - 201: {token, user: {id, username, email}}
/// - 400: Validação falhou ou username/email já existe
/// - 500: Erro interno
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final username = body['username'] as String?;
    final email = body['email'] as String?;
    final password = body['password'] as String?;

    // Validações básicas
    if (username == null || username.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'message': 'Nome de usuário é obrigatório'},
      );
    }

    if (email == null || email.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'message': 'Email é obrigatório'},
      );
    }

    if (password == null || password.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'message': 'Senha é obrigatória'},
      );
    }

    if (username.length < 3) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'message': 'Nome de usuário deve ter no mínimo 3 caracteres'},
      );
    }

    if (password.length < 6) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'message': 'Senha deve ter no mínimo 6 caracteres'},
      );
    }

    // Registrar no banco de dados
    final authService = AuthService();
    final result = await authService.register(
      username: username,
      email: email,
      password: password,
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: {
        'token': result['token'],
        'user': {
          'id': result['userId'],
          'username': result['username'],
          'email': result['email'],
        },
      },
    );
  } on Exception catch (e) {
    print('[ERROR] handler: $e');
    // Erros de negócio (username/email duplicado, etc)
    final message = e.toString().replaceFirst('Exception: ', '');
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': message},
    );
  } catch (e) {
    print('[ERROR] handler: $e');
    print('Erro ao criar conta: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'message': 'Erro ao criar conta'},
    );
  }
}
