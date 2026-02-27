import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

Future<void> main(List<String> args) async {
  final baseUrl = _arg(args, '--base-url') ?? 'http://localhost:8080';
  final durationSec = int.tryParse(_arg(args, '--duration-sec') ?? '60') ?? 60;
  final concurrency = int.tryParse(_arg(args, '--concurrency') ?? '20') ?? 20;

  print('▶️ Load test core endpoints');
  print('  baseUrl=$baseUrl');
  print('  duration=${durationSec}s');
  print('  concurrency=$concurrency');

  final endpoints = <String>[
    '/health/ready',
    '/sets?limit=20&page=1',
    '/cards?name=sol&limit=30&page=1',
  ];

  final stats = <String, _Stat>{
    for (final endpoint in endpoints) endpoint: _Stat(),
  };

  final stopAt = DateTime.now().add(Duration(seconds: durationSec));
  final client = http.Client();

  Future<void> worker() async {
    var idx = 0;
    while (DateTime.now().isBefore(stopAt)) {
      final endpoint = endpoints[idx % endpoints.length];
      idx++;
      final sw = Stopwatch()..start();
      try {
        final res = await client.get(Uri.parse('$baseUrl$endpoint')).timeout(
              const Duration(seconds: 12),
            );
        sw.stop();
        stats[endpoint]!.add(res.statusCode, sw.elapsedMilliseconds);
      } catch (_) {
        sw.stop();
        stats[endpoint]!.add(0, sw.elapsedMilliseconds);
      }
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
  client.close();

  print('\n📊 Results');
  final output = <String, dynamic>{};
  for (final entry in stats.entries) {
    final summary = entry.value.summary();
    output[entry.key] = summary;
    print('${entry.key}: $summary');
  }

  print('\nJSON:\n${const JsonEncoder.withIndent('  ').convert(output)}');
}

String? _arg(List<String> args, String key) {
  for (final arg in args) {
    if (arg.startsWith('$key=')) return arg.split('=').last.trim();
  }
  return null;
}

class _Stat {
  final List<int> latencies = [];
  int total = 0;
  int ok = 0;
  int errors = 0;

  void add(int statusCode, int latencyMs) {
    total++;
    latencies.add(latencyMs);
    if (statusCode >= 200 && statusCode < 400) {
      ok++;
    } else {
      errors++;
    }
  }

  Map<String, dynamic> summary() {
    latencies.sort();
    final p95 = latencies.isEmpty
        ? 0
        : latencies[(latencies.length * 0.95).floor().clamp(0, latencies.length - 1)];
    final avg = latencies.isEmpty
        ? 0
        : (latencies.reduce((a, b) => a + b) / latencies.length).round();
    return {
      'total_requests': total,
      'ok': ok,
      'errors': errors,
      'avg_latency_ms': avg,
      'p95_latency_ms': p95,
    };
  }
}
