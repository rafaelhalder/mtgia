import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

import 'auth_middleware.dart';
import 'plan_service.dart';

Middleware aiPlanLimitMiddleware() {
  return (handler) {
    return (context) async {
      final userId = getUserId(context);
      final pool = context.read<Pool>();
      final snapshot = await PlanService(pool).getSnapshot(userId);

      if (snapshot.status != 'active') {
        return Response.json(
          statusCode: HttpStatus.paymentRequired,
          body: {
            'error': 'Plano inativo',
            'message': 'Seu plano está inativo. Reative para continuar usando IA.',
            'plan_name': snapshot.planName,
            'status': snapshot.status,
          },
        );
      }

      if (snapshot.aiRequestsRemaining <= 0) {
        return Response.json(
          statusCode: HttpStatus.paymentRequired,
          body: {
            'error': 'Limite do plano atingido',
            'message':
                'Você atingiu o limite de requisições de IA do seu plano atual. Faça upgrade para continuar.',
            'plan_name': snapshot.planName,
            'ai_monthly_limit': snapshot.aiMonthlyLimit,
            'ai_requests_used': snapshot.aiRequestsUsed,
            'ai_requests_remaining': snapshot.aiRequestsRemaining,
            'upgrade_hint': 'Plano Pro libera mais capacidade de otimização.',
          },
          headers: {
            'X-Plan-Name': snapshot.planName,
            'X-Plan-Limit': snapshot.aiMonthlyLimit.toString(),
            'X-Plan-Used': snapshot.aiRequestsUsed.toString(),
          },
        );
      }

      final response = await handler(context);
      return response.copyWith(
        headers: {
          ...response.headers,
          'X-Plan-Name': snapshot.planName,
          'X-Plan-Limit': snapshot.aiMonthlyLimit.toString(),
          'X-Plan-Used': snapshot.aiRequestsUsed.toString(),
        },
      );
    };
  };
}
