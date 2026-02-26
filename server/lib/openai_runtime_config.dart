import 'package:dotenv/dotenv.dart';

class OpenAiRuntimeConfig {
  final DotEnv env;

  OpenAiRuntimeConfig(this.env);

  String get _profile {
    final explicit = env['OPENAI_PROFILE']?.trim().toLowerCase();
    if (explicit == 'dev' || explicit == 'staging' || explicit == 'prod') {
      return explicit!;
    }

    final environment = env['ENVIRONMENT']?.trim().toLowerCase();
    if (environment == 'production' || environment == 'prod') {
      return 'prod';
    }
    if (environment == 'staging' || environment == 'stage') {
      return 'staging';
    }
    return 'dev';
  }

  String modelFor({
    required String key,
    required String fallback,
    String? devFallback,
    String? stagingFallback,
    String? prodFallback,
  }) {
    final value = env[key]?.trim();
    if (value == null || value.isEmpty) {
      switch (_profile) {
        case 'dev':
          return devFallback ?? fallback;
        case 'staging':
          return stagingFallback ?? fallback;
        case 'prod':
          return prodFallback ?? fallback;
        default:
          return fallback;
      }
    }
    return value;
  }

  double temperatureFor({
    required String key,
    required double fallback,
    double? devFallback,
    double? stagingFallback,
    double? prodFallback,
  }) {
    final raw = env[key]?.trim();
    if (raw == null || raw.isEmpty) {
      switch (_profile) {
        case 'dev':
          return _clampTemp(devFallback ?? fallback);
        case 'staging':
          return _clampTemp(stagingFallback ?? fallback);
        case 'prod':
          return _clampTemp(prodFallback ?? fallback);
        default:
          return _clampTemp(fallback);
      }
    }

    final parsed = double.tryParse(raw);
    if (parsed == null) {
      return _clampTemp(fallback);
    }

    return _clampTemp(parsed);
  }

  double _clampTemp(double value) {
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }
}