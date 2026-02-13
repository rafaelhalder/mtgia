// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, implicit_dynamic_list_literal

import 'dart:io';

import 'package:dart_frog/dart_frog.dart';


import '../routes/index.dart' as index;
import '../routes/users/me/index.dart' as users_me_index;
import '../routes/users/me/fcm-token/index.dart' as users_me_fcm_token_index;
import '../routes/users/[id]/following/index.dart' as users_$id_following_index;
import '../routes/users/[id]/followers/index.dart' as users_$id_followers_index;
import '../routes/users/[id]/follow/index.dart' as users_$id_follow_index;
import '../routes/trades/index.dart' as trades_index;
import '../routes/trades/[id]/status.dart' as trades_$id_status;
import '../routes/trades/[id]/respond.dart' as trades_$id_respond;
import '../routes/trades/[id]/messages.dart' as trades_$id_messages;
import '../routes/trades/[id]/index.dart' as trades_$id_index;
import '../routes/sets/index.dart' as sets_index;
import '../routes/rules/index.dart' as rules_index;
import '../routes/notifications/read-all.dart' as notifications_read_all;
import '../routes/notifications/index.dart' as notifications_index;
import '../routes/notifications/count.dart' as notifications_count;
import '../routes/notifications/[id]/read.dart' as notifications_$id_read;
import '../routes/market/movers/index.dart' as market_movers_index;
import '../routes/market/card/[cardId].dart' as market_card_$card_id;
import '../routes/import/index.dart' as import_index;
import '../routes/import/validate/index.dart' as import_validate_index;
import '../routes/import/to-deck/index.dart' as import_to_deck_index;
import '../routes/health/index.dart' as health_index;
import '../routes/health/ready/index.dart' as health_ready_index;
import '../routes/health/live/index.dart' as health_live_index;
import '../routes/decks/index.dart' as decks_index;
import '../routes/decks/[id]/index.dart' as decks_$id_index;
import '../routes/decks/[id]/validate/index.dart' as decks_$id_validate_index;
import '../routes/decks/[id]/simulate/index.dart' as decks_$id_simulate_index;
import '../routes/decks/[id]/recommendations/index.dart' as decks_$id_recommendations_index;
import '../routes/decks/[id]/pricing/index.dart' as decks_$id_pricing_index;
import '../routes/decks/[id]/export/index.dart' as decks_$id_export_index;
import '../routes/decks/[id]/cards/index.dart' as decks_$id_cards_index;
import '../routes/decks/[id]/cards/set/index.dart' as decks_$id_cards_set_index;
import '../routes/decks/[id]/cards/replace/index.dart' as decks_$id_cards_replace_index;
import '../routes/decks/[id]/cards/bulk/index.dart' as decks_$id_cards_bulk_index;
import '../routes/decks/[id]/analysis/index.dart' as decks_$id_analysis_index;
import '../routes/decks/[id]/ai-analysis/index.dart' as decks_$id_ai_analysis_index;
import '../routes/conversations/index.dart' as conversations_index;
import '../routes/conversations/[id]/read.dart' as conversations_$id_read;
import '../routes/conversations/[id]/messages.dart' as conversations_$id_messages;
import '../routes/community/users/index.dart' as community_users_index;
import '../routes/community/users/[id].dart' as community_users_$id;
import '../routes/community/marketplace/index.dart' as community_marketplace_index;
import '../routes/community/decks/index.dart' as community_decks_index;
import '../routes/community/decks/[id].dart' as community_decks_$id;
import '../routes/community/binders/[userId].dart' as community_binders_$user_id;
import '../routes/cards/index.dart' as cards_index;
import '../routes/cards/resolve/index.dart' as cards_resolve_index;
import '../routes/cards/printings/index.dart' as cards_printings_index;
import '../routes/binder/index.dart' as binder_index;
import '../routes/binder/[id]/index.dart' as binder_$id_index;
import '../routes/auth/register.dart' as auth_register;
import '../routes/auth/me.dart' as auth_me;
import '../routes/auth/login.dart' as auth_login;
import '../routes/ai/weakness-analysis/index.dart' as ai_weakness_analysis_index;
import '../routes/ai/simulate-matchup/index.dart' as ai_simulate_matchup_index;
import '../routes/ai/simulate/index.dart' as ai_simulate_index;
import '../routes/ai/optimize/index.dart' as ai_optimize_index;
import '../routes/ai/ml-status/index.dart' as ai_ml_status_index;
import '../routes/ai/generate/index.dart' as ai_generate_index;
import '../routes/ai/explain/index.dart' as ai_explain_index;
import '../routes/ai/archetypes/index.dart' as ai_archetypes_index;

import '../routes/_middleware.dart' as middleware;
import '../routes/users/_middleware.dart' as users_middleware;
import '../routes/trades/_middleware.dart' as trades_middleware;
import '../routes/notifications/_middleware.dart' as notifications_middleware;
import '../routes/import/_middleware.dart' as import_middleware;
import '../routes/decks/_middleware.dart' as decks_middleware;
import '../routes/conversations/_middleware.dart' as conversations_middleware;
import '../routes/community/_middleware.dart' as community_middleware;
import '../routes/binder/_middleware.dart' as binder_middleware;
import '../routes/auth/_middleware.dart' as auth_middleware;
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
    ..mount('/ai/archetypes', (context) => buildAiArchetypesHandler()(context))
    ..mount('/ai/explain', (context) => buildAiExplainHandler()(context))
    ..mount('/ai/generate', (context) => buildAiGenerateHandler()(context))
    ..mount('/ai/ml-status', (context) => buildAiMlStatusHandler()(context))
    ..mount('/ai/optimize', (context) => buildAiOptimizeHandler()(context))
    ..mount('/ai/simulate', (context) => buildAiSimulateHandler()(context))
    ..mount('/ai/simulate-matchup', (context) => buildAiSimulateMatchupHandler()(context))
    ..mount('/ai/weakness-analysis', (context) => buildAiWeaknessAnalysisHandler()(context))
    ..mount('/auth', (context) => buildAuthHandler()(context))
    ..mount('/binder/<id>', (context,id,) => buildBinder$idHandler(id,)(context))
    ..mount('/binder', (context) => buildBinderHandler()(context))
    ..mount('/cards/printings', (context) => buildCardsPrintingsHandler()(context))
    ..mount('/cards/resolve', (context) => buildCardsResolveHandler()(context))
    ..mount('/cards', (context) => buildCardsHandler()(context))
    ..mount('/community/binders', (context) => buildCommunityBindersHandler()(context))
    ..mount('/community/decks', (context) => buildCommunityDecksHandler()(context))
    ..mount('/community/marketplace', (context) => buildCommunityMarketplaceHandler()(context))
    ..mount('/community/users', (context) => buildCommunityUsersHandler()(context))
    ..mount('/conversations/<id>', (context,id,) => buildConversations$idHandler(id,)(context))
    ..mount('/conversations', (context) => buildConversationsHandler()(context))
    ..mount('/decks/<id>/ai-analysis', (context,id,) => buildDecks$idAiAnalysisHandler(id,)(context))
    ..mount('/decks/<id>/analysis', (context,id,) => buildDecks$idAnalysisHandler(id,)(context))
    ..mount('/decks/<id>/cards/bulk', (context,id,) => buildDecks$idCardsBulkHandler(id,)(context))
    ..mount('/decks/<id>/cards/replace', (context,id,) => buildDecks$idCardsReplaceHandler(id,)(context))
    ..mount('/decks/<id>/cards/set', (context,id,) => buildDecks$idCardsSetHandler(id,)(context))
    ..mount('/decks/<id>/cards', (context,id,) => buildDecks$idCardsHandler(id,)(context))
    ..mount('/decks/<id>/export', (context,id,) => buildDecks$idExportHandler(id,)(context))
    ..mount('/decks/<id>/pricing', (context,id,) => buildDecks$idPricingHandler(id,)(context))
    ..mount('/decks/<id>/recommendations', (context,id,) => buildDecks$idRecommendationsHandler(id,)(context))
    ..mount('/decks/<id>/simulate', (context,id,) => buildDecks$idSimulateHandler(id,)(context))
    ..mount('/decks/<id>/validate', (context,id,) => buildDecks$idValidateHandler(id,)(context))
    ..mount('/decks/<id>', (context,id,) => buildDecks$idHandler(id,)(context))
    ..mount('/decks', (context) => buildDecksHandler()(context))
    ..mount('/health/live', (context) => buildHealthLiveHandler()(context))
    ..mount('/health/ready', (context) => buildHealthReadyHandler()(context))
    ..mount('/health', (context) => buildHealthHandler()(context))
    ..mount('/import/to-deck', (context) => buildImportToDeckHandler()(context))
    ..mount('/import/validate', (context) => buildImportValidateHandler()(context))
    ..mount('/import', (context) => buildImportHandler()(context))
    ..mount('/market/card', (context) => buildMarketCardHandler()(context))
    ..mount('/market/movers', (context) => buildMarketMoversHandler()(context))
    ..mount('/notifications/<id>', (context,id,) => buildNotifications$idHandler(id,)(context))
    ..mount('/notifications', (context) => buildNotificationsHandler()(context))
    ..mount('/rules', (context) => buildRulesHandler()(context))
    ..mount('/sets', (context) => buildSetsHandler()(context))
    ..mount('/trades/<id>', (context,id,) => buildTrades$idHandler(id,)(context))
    ..mount('/trades', (context) => buildTradesHandler()(context))
    ..mount('/users/<id>/follow', (context,id,) => buildUsers$idFollowHandler(id,)(context))
    ..mount('/users/<id>/followers', (context,id,) => buildUsers$idFollowersHandler(id,)(context))
    ..mount('/users/<id>/following', (context,id,) => buildUsers$idFollowingHandler(id,)(context))
    ..mount('/users/me/fcm-token', (context) => buildUsersMeFcmTokenHandler()(context))
    ..mount('/users/me', (context) => buildUsersMeHandler()(context))
    ..mount('/', (context) => buildHandler()(context));
  return pipeline.addHandler(router);
}

Handler buildAiArchetypesHandler() {
  final pipeline = const Pipeline().addMiddleware(ai_middleware.middleware);
  final router = Router()
    ..all('/', (context) => ai_archetypes_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildAiExplainHandler() {
  final pipeline = const Pipeline().addMiddleware(ai_middleware.middleware);
  final router = Router()
    ..all('/', (context) => ai_explain_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildAiGenerateHandler() {
  final pipeline = const Pipeline().addMiddleware(ai_middleware.middleware);
  final router = Router()
    ..all('/', (context) => ai_generate_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildAiMlStatusHandler() {
  final pipeline = const Pipeline().addMiddleware(ai_middleware.middleware);
  final router = Router()
    ..all('/', (context) => ai_ml_status_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildAiOptimizeHandler() {
  final pipeline = const Pipeline().addMiddleware(ai_middleware.middleware);
  final router = Router()
    ..all('/', (context) => ai_optimize_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildAiSimulateHandler() {
  final pipeline = const Pipeline().addMiddleware(ai_middleware.middleware);
  final router = Router()
    ..all('/', (context) => ai_simulate_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildAiSimulateMatchupHandler() {
  final pipeline = const Pipeline().addMiddleware(ai_middleware.middleware);
  final router = Router()
    ..all('/', (context) => ai_simulate_matchup_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildAiWeaknessAnalysisHandler() {
  final pipeline = const Pipeline().addMiddleware(ai_middleware.middleware);
  final router = Router()
    ..all('/', (context) => ai_weakness_analysis_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildAuthHandler() {
  final pipeline = const Pipeline().addMiddleware(auth_middleware.middleware);
  final router = Router()
    ..all('/register', (context) => auth_register.onRequest(context,))..all('/me', (context) => auth_me.onRequest(context,))..all('/login', (context) => auth_login.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildBinder$idHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(binder_middleware.middleware);
  final router = Router()
    ..all('/', (context) => binder_$id_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildBinderHandler() {
  final pipeline = const Pipeline().addMiddleware(binder_middleware.middleware);
  final router = Router()
    ..all('/', (context) => binder_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildCardsPrintingsHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => cards_printings_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildCardsResolveHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => cards_resolve_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildCardsHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => cards_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildCommunityBindersHandler() {
  final pipeline = const Pipeline().addMiddleware(community_middleware.middleware);
  final router = Router()
    ..all('/<userId>', (context,userId,) => community_binders_$user_id.onRequest(context,userId,));
  return pipeline.addHandler(router);
}

Handler buildCommunityDecksHandler() {
  final pipeline = const Pipeline().addMiddleware(community_middleware.middleware);
  final router = Router()
    ..all('/', (context) => community_decks_index.onRequest(context,))..all('/<id>', (context,id,) => community_decks_$id.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildCommunityMarketplaceHandler() {
  final pipeline = const Pipeline().addMiddleware(community_middleware.middleware);
  final router = Router()
    ..all('/', (context) => community_marketplace_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildCommunityUsersHandler() {
  final pipeline = const Pipeline().addMiddleware(community_middleware.middleware);
  final router = Router()
    ..all('/', (context) => community_users_index.onRequest(context,))..all('/<id>', (context,id,) => community_users_$id.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildConversations$idHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(conversations_middleware.middleware);
  final router = Router()
    ..all('/read', (context) => conversations_$id_read.onRequest(context,id,))..all('/messages', (context) => conversations_$id_messages.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildConversationsHandler() {
  final pipeline = const Pipeline().addMiddleware(conversations_middleware.middleware);
  final router = Router()
    ..all('/', (context) => conversations_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idAiAnalysisHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_ai_analysis_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idAnalysisHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_analysis_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idCardsBulkHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_cards_bulk_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idCardsReplaceHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_cards_replace_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idCardsSetHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_cards_set_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idCardsHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_cards_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idExportHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_export_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildDecks$idPricingHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_pricing_index.onRequest(context,id,));
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

Handler buildDecks$idValidateHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(decks_middleware.middleware);
  final router = Router()
    ..all('/', (context) => decks_$id_validate_index.onRequest(context,id,));
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

Handler buildHealthLiveHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => health_live_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildHealthReadyHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => health_ready_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildHealthHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => health_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildImportToDeckHandler() {
  final pipeline = const Pipeline().addMiddleware(import_middleware.middleware);
  final router = Router()
    ..all('/', (context) => import_to_deck_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildImportValidateHandler() {
  final pipeline = const Pipeline().addMiddleware(import_middleware.middleware);
  final router = Router()
    ..all('/', (context) => import_validate_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildImportHandler() {
  final pipeline = const Pipeline().addMiddleware(import_middleware.middleware);
  final router = Router()
    ..all('/', (context) => import_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildMarketCardHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/<cardId>', (context,cardId,) => market_card_$card_id.onRequest(context,cardId,));
  return pipeline.addHandler(router);
}

Handler buildMarketMoversHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => market_movers_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildNotifications$idHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(notifications_middleware.middleware);
  final router = Router()
    ..all('/read', (context) => notifications_$id_read.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildNotificationsHandler() {
  final pipeline = const Pipeline().addMiddleware(notifications_middleware.middleware);
  final router = Router()
    ..all('/read-all', (context) => notifications_read_all.onRequest(context,))..all('/', (context) => notifications_index.onRequest(context,))..all('/count', (context) => notifications_count.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildRulesHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => rules_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildSetsHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => sets_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildTrades$idHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(trades_middleware.middleware);
  final router = Router()
    ..all('/status', (context) => trades_$id_status.onRequest(context,id,))..all('/respond', (context) => trades_$id_respond.onRequest(context,id,))..all('/messages', (context) => trades_$id_messages.onRequest(context,id,))..all('/', (context) => trades_$id_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildTradesHandler() {
  final pipeline = const Pipeline().addMiddleware(trades_middleware.middleware);
  final router = Router()
    ..all('/', (context) => trades_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildUsers$idFollowHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(users_middleware.middleware);
  final router = Router()
    ..all('/', (context) => users_$id_follow_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildUsers$idFollowersHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(users_middleware.middleware);
  final router = Router()
    ..all('/', (context) => users_$id_followers_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildUsers$idFollowingHandler(String id,) {
  final pipeline = const Pipeline().addMiddleware(users_middleware.middleware);
  final router = Router()
    ..all('/', (context) => users_$id_following_index.onRequest(context,id,));
  return pipeline.addHandler(router);
}

Handler buildUsersMeFcmTokenHandler() {
  final pipeline = const Pipeline().addMiddleware(users_middleware.middleware);
  final router = Router()
    ..all('/', (context) => users_me_fcm_token_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildUsersMeHandler() {
  final pipeline = const Pipeline().addMiddleware(users_middleware.middleware);
  final router = Router()
    ..all('/', (context) => users_me_index.onRequest(context,));
  return pipeline.addHandler(router);
}

Handler buildHandler() {
  final pipeline = const Pipeline();
  final router = Router()
    ..all('/', (context) => index.onRequest(context,));
  return pipeline.addHandler(router);
}

