import 'package:postgres/postgres.dart';

bool? _hasDeckMetaColumnsCache;
bool? _hasDeckPricingColumnsCache;

Future<bool> hasDeckMetaColumns(Pool pool) async {
  if (_hasDeckMetaColumnsCache != null) return _hasDeckMetaColumnsCache!;
  try {
    final result = await pool.execute(
      Sql.named('''
        SELECT COUNT(*)::int
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'decks'
          AND column_name IN ('archetype', 'bracket')
      '''),
    );
    final count = (result.first[0] as int?) ?? 0;
    _hasDeckMetaColumnsCache = count >= 2;
  } catch (_) {
    _hasDeckMetaColumnsCache = false;
  }
  return _hasDeckMetaColumnsCache!;
}

Future<bool> hasDeckPricingColumns(Pool pool) async {
  if (_hasDeckPricingColumnsCache != null) return _hasDeckPricingColumnsCache!;
  try {
    final result = await pool.execute(
      Sql.named('''
        SELECT COUNT(*)::int
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'decks'
          AND column_name IN ('pricing_currency','pricing_total','pricing_missing_cards','pricing_updated_at')
      '''),
    );
    final count = (result.first[0] as int?) ?? 0;
    _hasDeckPricingColumnsCache = count >= 4;
  } catch (_) {
    _hasDeckPricingColumnsCache = false;
  }
  return _hasDeckPricingColumnsCache!;
}
