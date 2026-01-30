import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';

import '../lib/database.dart';

/// Sincroniza as Comprehensive Rules (Wizards) para a tabela `rules`.
///
/// Fonte: https://magic.wizards.com/en/rules (links para MagicCompRules *.txt)
///
/// Uso:
///   dart run bin/sync_rules.dart
///   dart run bin/sync_rules.dart --force
///   dart run bin/sync_rules.dart --from-file=magicrules.txt
///
/// O script:
/// - Descobre a URL mais recente do .txt (por data no nome do arquivo)
/// - Baixa e salva em `server/magicrules.txt` (cache local)
/// - Faz TRUNCATE da tabela `rules` e reimporta todas as regras
/// - Atualiza `sync_state` com metadados (rules_source_url, rules_version_date, rules_last_sync_at)
const _rulesPageUrl = 'https://magic.wizards.com/en/rules';
final _rulesTxtUrlRegex = RegExp(
    r'https://media\.wizards\.com/\d{4}/downloads/MagicCompRules \d{8}\.txt');

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
sync_rules.dart - Sincroniza as Comprehensive Rules para o Postgres

Uso:
  dart run bin/sync_rules.dart
  dart run bin/sync_rules.dart --force
  dart run bin/sync_rules.dart --from-file=magicrules.txt

Opções:
  --force               Força re-download mesmo se a versão não mudou
  --from-file=<path>    Importa de um arquivo local (sem baixar)
  --help                Mostra esta ajuda
''');
    return;
  }

  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();
  final environment = (env['ENVIRONMENT'] ??
          Platform.environment['ENVIRONMENT'] ??
          'development')
      .toLowerCase();
  final force = args.contains('--force') || args.contains('-f');
  final fromFile = _parseFromFile(args);

  stdout.writeln(
      '📚 Sync de regras (ENVIRONMENT=$environment)${force ? ' [FORÇADO]' : ''}');

  final db = Database();
  await db.connect();
  final pool = db.connection;

  try {
    await _ensureSyncStateTable(pool);
    await _ensureRulesIndexes(pool);

    final (rulesText, sourceUrl, versionDate) =
        await _loadRulesText(fromFile: fromFile);

    final lastVersionDate = await _getSyncState(pool, 'rules_version_date');
    if (!force && versionDate != null && lastVersionDate == versionDate) {
      stdout.writeln(
          '✅ Regras já estão atualizadas (rules_version_date=$versionDate). Nada a fazer.');
      return;
    }

    final parsed = _parseRules(rulesText);
    stdout.writeln('🔎 Regras parseadas: ${parsed.length}');

    await pool.runTx((session) async {
      await session.execute(Sql.named('TRUNCATE TABLE rules'));

      const batchSize = 500;
      for (var i = 0; i < parsed.length; i += batchSize) {
        final batch =
            parsed.sublist(i, (i + batchSize).clamp(0, parsed.length));
        for (final rule in batch) {
          await session.execute(
            Sql.named(
                'INSERT INTO rules (title, description, category) VALUES (@t, @d, @c)'),
            parameters: {
              't': rule.title,
              'd': rule.description,
              'c': rule.category,
            },
          );
        }
        stdout.write(
            '\r⬆️  Importando... ${(i + batch.length)}/${parsed.length}');
      }
    });
    stdout.writeln('\n✅ Importação concluída.');

    if (sourceUrl != null) {
      await _setSyncState(pool, 'rules_source_url', sourceUrl);
    }
    if (versionDate != null) {
      await _setSyncState(pool, 'rules_version_date', versionDate);
    }
    await _setSyncState(
        pool, 'rules_last_sync_at', DateTime.now().toIso8601String());
  } finally {
    await db.close();
  }
}

String? _parseFromFile(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--from-file=')) {
      final value = arg.split('=').last.trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

Future<(String rulesText, String? sourceUrl, String? versionDate)>
    _loadRulesText({String? fromFile}) async {
  if (fromFile != null) {
    final file = File(fromFile);
    if (!await file.exists()) {
      throw Exception('Arquivo não encontrado: $fromFile');
    }
    final text = await file.readAsString();
    return (text, null, null);
  }

  final (latestUrl, versionDate) = await _discoverLatestRulesTxtUrl();
  final encodedUrl = latestUrl.replaceAll(' ', '%20');
  stdout.writeln('⬇️  Baixando rules: $latestUrl');

  final res = await http.get(Uri.parse(encodedUrl));
  if (res.statusCode != 200) {
    throw Exception('Falha ao baixar rules txt: ${res.statusCode}');
  }

  final text = utf8.decode(res.bodyBytes);

  // Cache local para facilitar debug/offline (mantém compat com bin/seed_rules.dart).
  final cacheFile = File('magicrules.txt');
  await cacheFile.writeAsString(text);

  return (text, latestUrl, versionDate);
}

Future<(String url, String? versionDate)> _discoverLatestRulesTxtUrl() async {
  final res = await http.get(Uri.parse(_rulesPageUrl));
  if (res.statusCode != 200) {
    throw Exception('Falha ao carregar página de rules: ${res.statusCode}');
  }
  final html = utf8.decode(res.bodyBytes);

  final matches = _rulesTxtUrlRegex
      .allMatches(html)
      .map((m) => m.group(0)!)
      .toSet()
      .toList();
  if (matches.isEmpty) {
    throw Exception(
        'Não encontrei link .txt de regras na página $_rulesPageUrl');
  }

  String best = matches.first;
  String? bestDate = _extractRulesDate(best);

  for (final url in matches.skip(1)) {
    final date = _extractRulesDate(url);
    if (bestDate == null) {
      best = url;
      bestDate = date;
      continue;
    }
    if (date != null && date.compareTo(bestDate) > 0) {
      best = url;
      bestDate = date;
    }
  }

  return (best, bestDate);
}

String? _extractRulesDate(String url) {
  final match = RegExp(r'(\d{8})\.txt$').firstMatch(url);
  return match?.group(1);
}

List<_RuleRow> _parseRules(String text) {
  final lines = const LineSplitter().convert(text);

  var currentCategory = 'General';
  String? currentRuleNumber;
  final currentRuleText = StringBuffer();

  final majorSectionRegex = RegExp(r'^(\d)\.\s+(.*)'); // "1. Game Concepts"
  final subSectionRegex = RegExp(r'^(\d{3})\.\s+(.*)'); // "100. General"
  final ruleRegex =
      RegExp(r'^(\d{3}\.\d+[a-z]?)\.?\s+(.*)'); // "100.1" or "100.1a"

  final out = <_RuleRow>[];

  void flush() {
    final title = currentRuleNumber;
    if (title == null) return;
    final desc = currentRuleText.toString().trim();
    if (desc.isEmpty) return;
    out.add(
        _RuleRow(title: title, description: desc, category: currentCategory));
  }

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    final majorMatch = majorSectionRegex.firstMatch(line);
    if (majorMatch != null) {
      flush();
      currentRuleNumber = null;
      currentRuleText.clear();
      currentCategory = majorMatch.group(2) ?? 'General';
      continue;
    }

    final subMatch = subSectionRegex.firstMatch(line);
    if (subMatch != null) {
      flush();
      currentRuleNumber = null;
      currentRuleText.clear();
      currentCategory = subMatch.group(2) ?? currentCategory;
      continue;
    }

    final ruleMatch = ruleRegex.firstMatch(line);
    if (ruleMatch != null) {
      flush();
      currentRuleNumber = ruleMatch.group(1);
      currentRuleText.clear();
      currentRuleText.write(ruleMatch.group(2));
      continue;
    }

    if (currentRuleNumber != null) {
      currentRuleText.write('\n$line');
    }
  }

  flush();
  return out;
}

Future<void> _ensureRulesIndexes(Pool pool) async {
  await pool.execute(
      Sql.named('CREATE INDEX IF NOT EXISTS idx_rules_title ON rules (title)'));
  await pool.execute(Sql.named(
      'CREATE INDEX IF NOT EXISTS idx_rules_category ON rules (category)'));
}

Future<void> _ensureSyncStateTable(Pool pool) async {
  await pool.execute(
    Sql.named('''
      CREATE TABLE IF NOT EXISTS sync_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      )
    '''),
  );
}

Future<String?> _getSyncState(Pool pool, String key) async {
  final res = await pool.execute(
    Sql.named('SELECT value FROM sync_state WHERE key = @k LIMIT 1'),
    parameters: {'k': key},
  );
  if (res.isEmpty) return null;
  return res.first.toColumnMap()['value']?.toString();
}

Future<void> _setSyncState(Pool pool, String key, String value) async {
  await pool.execute(
    Sql.named('''
      INSERT INTO sync_state (key, value, updated_at)
      VALUES (@k, @v, CURRENT_TIMESTAMP)
      ON CONFLICT (key) DO UPDATE
      SET value = EXCLUDED.value,
          updated_at = CURRENT_TIMESTAMP
    '''),
    parameters: {'k': key, 'v': value},
  );
}

class _RuleRow {
  const _RuleRow(
      {required this.title, required this.description, required this.category});

  final String title;
  final String description;
  final String category;
}
