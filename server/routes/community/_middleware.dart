import 'package:dart_frog/dart_frog.dart';

/// Middleware para rotas de comunidade.
/// Sem autenticação obrigatória — a listagem e visualização de decks
/// públicos é aberta. Rotas que precisam de auth (ex: /copy) usam
/// autenticação opcional aqui e checam no handler.
Handler middleware(Handler handler) {
  return handler;
}
