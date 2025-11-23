// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, implicit_dynamic_list_literal

import 'dart:io';

import 'package:dart_frog/dart_frog.dart';


import '../routes/index.dart' as index;
import '../routes/users/register.dart' as users_register;
import '../routes/users/login.dart' as users_login;
import '../routes/rules/index.dart' as rules_index;
import '../routes/import/index.dart' as import_index;
import '../routes/decks/index.dart' as decks_index;
import '../routes/decks/[id]/index.dart' as decks_$id_index;
import '../routes/decks/[id]/simulate/index.dart' as decks_$id_simulate_index;
import '../routes/decks/[id]/recommendations/index.dart' as decks_$id_recommendations_index;
import '../routes/decks/[id]/analysis/index.dart' as decks_$id_analysis_index;
import '../routes/cards/index.dart' as cards_index;
import '../routes/auth/register.dart' as auth_register;
import '../routes/auth/login.dart' as auth_login;
import '../routes/ai/generate/index.dart' as ai_generate_index;

import '../routes/_middleware.dart' as middleware;
import '../routes/import/_middleware.dart' as import_middleware;
import '../routes/decks/_middleware.dart' as decks_middleware;
import '../routes/ai/_middleware.dart' as ai_middleware;

void main() async {
  final address = InternetAddress.tryParse('') ?? InternetAddress.anyIPv6;
  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  hotReload(() => createServer(address, port));
}

Future<HttpServer> createServer(InternetAddress address, int port) {
  final handler = Cascade().add(buildRootHandler()).handler;
  return serve(handler, address, port);
}

Handler buildRootHandler() {
  final pipeline = const Pipeline().addMiddleware(middleware.middleware);
  final router = Router()
    ..mount('/ai/generate', (context) => buildAiGenerateHandler()(context))
    ..mount('/auth', (context) => buildAuthHandler()(context))
    ..mount('/cards', (context) => buildCardsHandler()(context))
    ..mount('/decks/<id>/analysis', (context,id,) => buildDecks$idAnalysisHandler(id,)(context))
    ..mount('/decks/<id>/recommendations', (context,id,) => buildDecks$idRecommendationsHandler(id,)(context))
    ..mount('/decks/<id>/simulate', (context,id,) => buildDecks$idSimulateHandler(id,)(context))
    ..mount('/decks/<id>', (context,id,) => buildDecks$idHandler(id,)(context))
    ..mount('/decks', (context) => buildDecksHandler()(context))
    ..mount('/import', (context) => buildImportHandler()(context))
    ..mount('/rules', (context) => buildRulesHandler()(context))
    ..mount('/users', (context) => buildUsersHandler()(context))
    ..mount('/', (context) => buildHandler()(context));
  return pipeline.addHandler(router);
}

Handler buildAiGenerateHandler() {
  final pipeline = const Pipeline().addMiddleware(ai_middleware.middleware);
  final router = Router()
    ..all('/', (context) => ai_generate_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildAuthHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/register', (context) => auth_register.onRequest(context,))..all('/login', (context) => auth_login.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildCardsHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => cards_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idAnalysisHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_analysis_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idRecommendationsHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_recommendations_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idSimulateHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_simulate_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildDecksHandler() {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildImportHandler() {
  final pipeline = const Pipeline().addMiddleware(import_middleware.middleware);
  final router = Router()
    ..all('/', (context) => import_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildRulesHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => rules_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildUsersHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/register', (context) => users_register.onRequest(context,))..all('/login', (context) => users_login.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => index.onRequest(context,));
  return pipeline.addHandler(router);
}

