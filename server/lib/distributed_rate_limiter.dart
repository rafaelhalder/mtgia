import 'package:postgres/postgres.dart';

class DistributedRateLimiter {
  final Pool pool;
  final String bucket;
  final int maxRequests;
  final int windowSeconds;

  const DistributedRateLimiter({
    required this.pool,
    required this.bucket,
    required this.maxRequests,
    required this.windowSeconds,
  });

  Future<bool> isAllowed(String identifier) async {
    await pool.execute(
      Sql.named('''
        INSERT INTO rate_limit_events (bucket, identifier, created_at)
        VALUES (@bucket, @identifier, NOW())
      '''),
      parameters: {
        'bucket': bucket,
        'identifier': identifier,
      },
    );

    final countResult = await pool.execute(
      Sql.named('''
        SELECT COUNT(*)::int AS c
        FROM rate_limit_events
        WHERE bucket = @bucket
          AND identifier = @identifier
          AND created_at >= NOW() - (CAST(@window_seconds AS int) * INTERVAL '1 second')
      '''),
      parameters: {
        'bucket': bucket,
        'identifier': identifier,
        'window_seconds': windowSeconds,
      },
    );

    final count = (countResult.first.toColumnMap()['c'] as int?) ?? 0;

    await pool.execute(
      Sql.named('''
        DELETE FROM rate_limit_events
        WHERE bucket = @bucket
          AND identifier = @identifier
          AND created_at < NOW() - (CAST(@window_seconds AS int) * INTERVAL '2 second')
      '''),
      parameters: {
        'bucket': bucket,
        'identifier': identifier,
        'window_seconds': windowSeconds,
      },
    );

    return count <= maxRequests;
  }
}
