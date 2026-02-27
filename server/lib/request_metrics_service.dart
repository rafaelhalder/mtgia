import 'dart:math';

class EndpointMetricSnapshot {
  final int requestCount;
  final int errorCount;
  final double avgLatencyMs;
  final int p95LatencyMs;
  final DateTime lastRequestAt;

  const EndpointMetricSnapshot({
    required this.requestCount,
    required this.errorCount,
    required this.avgLatencyMs,
    required this.p95LatencyMs,
    required this.lastRequestAt,
  });

  Map<String, dynamic> toJson() => {
        'request_count': requestCount,
        'error_count': errorCount,
        'error_rate': requestCount == 0 ? 0.0 : errorCount / requestCount,
        'avg_latency_ms': avgLatencyMs,
        'p95_latency_ms': p95LatencyMs,
        'last_request_at': lastRequestAt.toIso8601String(),
      };
}

class _EndpointMetricBucket {
  int requestCount = 0;
  int errorCount = 0;
  int latencyTotalMs = 0;
  DateTime lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);
  final List<int> recentLatencies = <int>[];

  void add({required int latencyMs, required bool isError}) {
    requestCount += 1;
    if (isError) errorCount += 1;
    latencyTotalMs += latencyMs;
    lastRequestAt = DateTime.now().toUtc();

    recentLatencies.add(latencyMs);
    if (recentLatencies.length > 200) {
      recentLatencies.removeAt(0);
    }
  }

  EndpointMetricSnapshot snapshot() {
    final sorted = [...recentLatencies]..sort();
    final p95Index = sorted.isEmpty ? 0 : max(0, (sorted.length * 0.95).ceil() - 1);
    final p95 = sorted.isEmpty ? 0 : sorted[p95Index];

    return EndpointMetricSnapshot(
      requestCount: requestCount,
      errorCount: errorCount,
      avgLatencyMs: requestCount == 0 ? 0 : latencyTotalMs / requestCount,
      p95LatencyMs: p95,
      lastRequestAt: lastRequestAt,
    );
  }
}

class RequestMetricsService {
  RequestMetricsService._();
  static final RequestMetricsService instance = RequestMetricsService._();

  final Map<String, _EndpointMetricBucket> _metrics =
      <String, _EndpointMetricBucket>{};

  void record({
    required String endpoint,
    required int statusCode,
    required int latencyMs,
  }) {
    final bucket = _metrics.putIfAbsent(endpoint, () => _EndpointMetricBucket());
    bucket.add(
      latencyMs: latencyMs,
      isError: statusCode >= 500,
    );
  }

  Map<String, dynamic> snapshot() {
    final entries = _metrics.entries.toList()
      ..sort((a, b) => b.value.requestCount.compareTo(a.value.requestCount));

    var totalRequests = 0;
    var totalErrors = 0;

    final endpointMetrics = <String, dynamic>{};
    for (final entry in entries) {
      final snap = entry.value.snapshot();
      totalRequests += snap.requestCount;
      totalErrors += snap.errorCount;
      endpointMetrics[entry.key] = snap.toJson();
    }

    return {
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'totals': {
        'request_count': totalRequests,
        'error_count': totalErrors,
        'error_rate': totalRequests == 0 ? 0.0 : totalErrors / totalRequests,
      },
      'endpoints': endpointMetrics,
    };
  }
}
