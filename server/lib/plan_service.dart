import 'package:postgres/postgres.dart';

class UserPlanSnapshot {
  const UserPlanSnapshot({
    required this.planName,
    required this.status,
    required this.aiMonthlyLimit,
    required this.aiRequestsUsed,
    required this.aiRequestsRemaining,
    required this.estimatedCostUsd,
  });

  final String planName;
  final String status;
  final int aiMonthlyLimit;
  final int aiRequestsUsed;
  final int aiRequestsRemaining;
  final double estimatedCostUsd;

  Map<String, dynamic> toJson() => {
        'plan_name': planName,
        'status': status,
        'ai_monthly_limit': aiMonthlyLimit,
        'ai_requests_used': aiRequestsUsed,
        'ai_requests_remaining': aiRequestsRemaining,
        'estimated_cost_usd': estimatedCostUsd,
      };
}

class PlanService {
  const PlanService(this.pool);

  final Pool pool;

  static const _defaultFreeLimit = 120;
  static const _proLimit = 2500;

  Future<void> ensureFreePlan(String userId) async {
    await pool.execute(
      Sql.named('''
        INSERT INTO user_plans (user_id, plan_name, status)
        VALUES (@userId, 'free', 'active')
        ON CONFLICT (user_id) DO NOTHING
      '''),
      parameters: {'userId': userId},
    );
  }

  Future<UserPlanSnapshot> getSnapshot(String userId) async {
    await ensureFreePlan(userId);

    final planResult = await pool.execute(
      Sql.named('''
        SELECT plan_name, status
        FROM user_plans
        WHERE user_id = @userId
        LIMIT 1
      '''),
      parameters: {'userId': userId},
    );

    final planName =
        planResult.isNotEmpty ? (planResult.first[0] as String? ?? 'free') : 'free';
    final status =
        planResult.isNotEmpty ? (planResult.first[1] as String? ?? 'active') : 'active';

    final aiMonthlyLimit = planName == 'pro' ? _proLimit : _defaultFreeLimit;

    final usageResult = await pool.execute(
      Sql.named('''
        SELECT
          COUNT(*)::int AS requests_used,
          COALESCE(SUM(COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0)), 0)::int AS total_tokens
        FROM ai_logs
        WHERE user_id = @userId
          AND created_at >= NOW() - INTERVAL '30 days'
      '''),
      parameters: {'userId': userId},
    );

    final requestsUsed = usageResult.isNotEmpty ? (usageResult.first[0] as int? ?? 0) : 0;
    final totalTokens = usageResult.isNotEmpty ? (usageResult.first[1] as int? ?? 0) : 0;

    final remaining = (aiMonthlyLimit - requestsUsed).clamp(0, aiMonthlyLimit);

    final estimatedCostUsd = ((totalTokens / 1000.0) * 0.002);

    return UserPlanSnapshot(
      planName: planName,
      status: status,
      aiMonthlyLimit: aiMonthlyLimit,
      aiRequestsUsed: requestsUsed,
      aiRequestsRemaining: remaining,
      estimatedCostUsd: double.parse(estimatedCostUsd.toStringAsFixed(4)),
    );
  }
}
