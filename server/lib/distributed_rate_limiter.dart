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
    final countResult = await pool.runTx((session) {
      return session.execute(
        Sql.named('''
          WITH lock_row AS (
            SELECT pg_advisory_xact_lock(hashtext(@lock_key))
          ),
          deleted AS (
            DELETE FROM rate_limit_events
            WHERE bucket = @bucket
              AND identifier = @identifier
              AND created_at < NOW() - (CAST(@window_seconds AS int) * INTERVAL '2 second')
          ),
          inserted AS (
            INSERT INTO rate_limit_events (bucket, identifier, created_at)
            VALUES (@bucket, @identifier, NOW())
            RETURNING 1
          )
          SELECT COUNT(*)::int AS c
          FROM rate_limit_events, lock_row
          WHERE bucket = @bucket
            AND identifier = @identifier
            AND created_at >= NOW() - (CAST(@window_seconds AS int) * INTERVAL '1 second')
        '''),
        parameters: {
          'bucket': bucket,
          'identifier': identifier,
          'window_seconds': windowSeconds,
          'lock_key': '$bucket:$identifier',
        },
      );
    });

    final count = (countResult.first.toColumnMap()['c'] as int?) ?? 0;

    return count <= maxRequests;
  }
}
