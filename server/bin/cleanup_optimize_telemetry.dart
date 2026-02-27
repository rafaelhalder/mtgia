// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:postgres/postgres.dart';

void main(List<String> args) async {
  final env = DotEnv(includePlatformEnvironment: true, quiet: true)..load();

  final retentionArg = args.firstWhere(
    (a) => a.startsWith('--retention-days='),
    orElse: () => '',
  );
  final dryRun = args.contains('--dry-run');

  final retentionFromArg = retentionArg.isNotEmpty
      ? int.tryParse(retentionArg.split('=').last.trim())
      : null;
  final retentionFromEnv = int.tryParse(env['TELEMETRY_RETENTION_DAYS'] ?? '');
  final retentionDays = retentionFromArg ?? retentionFromEnv ?? 180;

  if (retentionDays < 1) {
    print('❌ retention-days inválido. Use um inteiro >= 1.');
    exit(1);
  }

  final host = env['DB_HOST'];
  final port = int.tryParse(env['DB_PORT'] ?? '');
  final database = env['DB_NAME'];
  final username = env['DB_USER'];
  final password = env['DB_PASS'];

  if (host == null ||
      port == null ||
      database == null ||
      username == null ||
      password == null) {
    print('❌ Variáveis de DB ausentes (DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASS).');
    exit(1);
  }

  final connection = await Connection.open(
    Endpoint(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );

  try {
    print('🧹 Cleanup optimize telemetry (retention_days=$retentionDays, dry_run=$dryRun)');

    final countResult = await connection.execute(
      Sql.named('''
        SELECT COUNT(*)::int AS c
        FROM ai_optimize_fallback_telemetry
        WHERE created_at < NOW() - (CAST(@days AS int) * INTERVAL '1 day')
      '''),
      parameters: {'days': retentionDays},
    );

    final toDelete = _toInt(countResult.first.toColumnMap()['c']);
    print('📊 Registros elegíveis para remoção: $toDelete');

    if (dryRun || toDelete == 0) {
      print('✅ Nenhuma remoção executada.');
      return;
    }

    final deleteResult = await connection.execute(
      Sql.named('''
        DELETE FROM ai_optimize_fallback_telemetry
        WHERE created_at < NOW() - (CAST(@days AS int) * INTERVAL '1 day')
      '''),
      parameters: {'days': retentionDays},
    );

    final deleted = deleteResult.affectedRows;
    print('✅ Remoção concluída. Registros removidos: $deleted');
  } catch (e) {
    print('❌ Falha no cleanup: $e');
    exit(1);
  } finally {
    await connection.close();
  }
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}
