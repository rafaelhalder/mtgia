import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import '../../lib/auth_service.dart';

/// Login com autenticação real no banco de dados
/// 
/// POST /auth/login
/// Body: {"email": "user@example.com", "password": "senha123"}
/// 
/// Retorna:
/// - 200: {token, user: {id, username, email}}
/// - 400: Validação falhou
/// - 401: Credenciais inválidas
/// - 500: Erro interno
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final email = body['email'] as String?;
    final password = body['password'] as String?;

    // Validação básica
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

    // Autenticar com banco de dados
    final authService = AuthService();
    final result = await authService.login(
      email: email,
      password: password,
    );

    return Response.json(
      statusCode: HttpStatus.ok,
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
    // Erros de negócio (credenciais inválidas, etc)
    final message = e.toString().replaceFirst('Exception: ', '');
    
    if (message.contains('Credenciais inválidas')) {
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'message': message},
      );
    }
    
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'message': message},
    );
  } catch (e) {
    print('Erro ao fazer login: $e');
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'message': 'Erro ao fazer login'},
    );
  }
}
