import 'sync_prices.dart' as sync;

/// Script legado: mantido por compatibilidade.
///
/// Use:
///   dart run bin/sync_prices.dart
Future<void> main(List<String> args) async {
  await sync.main(args);
}
