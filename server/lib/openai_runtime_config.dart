import 'package:dotenv/dotenv.dart';

class OpenAiRuntimeConfig {
  final DotEnv env;

  OpenAiRuntimeConfig(this.env);

  String modelFor({required String key, required String fallback}) {
    final value = env[key]?.trim();
    if (value == null || value.isEmpty) {
      return fallback;
    }
    return value;
  }

  double temperatureFor({required String key, required double fallback}) {
    final raw = env[key]?.trim();
    if (raw == null || raw.isEmpty) {
      return fallback;
    }

    final parsed = double.tryParse(raw);
    if (parsed == null) {
      return fallback;
    }

    if (parsed < 0) return 0;
    if (parsed > 1) return 1;
    return parsed;
  }
}