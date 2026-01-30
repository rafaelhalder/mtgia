import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';

import '../lib/database.dart';

Future<void> main(List<String> args) async {
  final jsonOutput = args.contains('--json');
  final limit = _parseIntArg(args, '--limit') ?? 10;

  final db = Database();
  await db.connect();
  final pool = db.connection;

  try {
    final stateRows = await pool.execute(
      Sql.named('SELECT key, value, updated_at FROM sync_state ORDER BY updated_at DESC'),
    );

    final hasSyncLog = await _hasTable(pool, 'sync_log');

    final logRows = hasSyncLog
        ? await pool.execute(
            Sql.named('''
              SELECT
                sync_type,
                status,
                records_inserted,
                records_updated,
                records_deleted,
                started_at,
                finished_at,
                error_message
              FROM sync_log
              ORDER BY started_at DESC
              LIMIT @limit
            '''),
            parameters: {'limit': limit},
          )
        : const <List<dynamic>>[];

    if (jsonOutput) {
      final payload = <String, dynamic>{
        'sync_state': [
          for (final row in stateRows)
            {
              'key': row[0],
              'value': row[1],
              'updated_at': row[2]?.toString(),
            }
        ],
        'sync_log': [
          for (final row in logRows)
            {
              'sync_type': row[0],
              'status': row[1],
              'records_inserted': row[2],
              'records_updated': row[3],
              'records_deleted': row[4],
              'started_at': row[5]?.toString(),
              'finished_at': row[6]?.toString(),
              'error_message': row[7],
            }
        ],
      };
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
      return;
    }

    stdout.writeln('sync_state:');
    if (stateRows.isEmpty) {
      stdout.writeln('  (vazio)');
    } else {
      for (final row in stateRows) {
        stdout.writeln('  - ${row[0]} = ${row[1]} (updated_at=${row[2]})');
      }
    }

    stdout.writeln('');
    stdout.writeln('sync_log (últimas $limit):');
    if (!hasSyncLog) {
      stdout.writeln('  (tabela sync_log não encontrada)');
    } else if (logRows.isEmpty) {
      stdout.writeln('  (vazio)');
    } else {
      for (final row in logRows) {
        stdout.writeln(
          '  - ${row[0]}: ${row[1]} (ins=${row[2]}, upd=${row[3]}, del=${row[4]}) started_at=${row[5]} finished_at=${row[6]}',
        );
        final error = row[7];
        if (error != null && error.toString().trim().isNotEmpty) {
          stdout.writeln('      error: $error');
        }
      }
    }
  } finally {
    await db.close();
  }
}

int? _parseIntArg(List<String> args, String key) {
  for (final arg in args) {
    if (arg.startsWith('$key=')) {
      final raw = arg.split('=').last.trim();
      return int.tryParse(raw);
    }
  }
  return null;
}

Future<bool> _hasTable(Pool pool, String tableName) async {
  try {
    final result = await pool.execute(
      Sql.named('SELECT to_regclass(@name)::text'),
      parameters: {'name': 'public.$tableName'},
    );
    final value = result.isNotEmpty ? result.first[0] : null;
    return value != null;
  } catch (_) {
    return false;
  }
}
