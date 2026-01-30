import 'dart:io';

import 'package:dotenv/dotenv.dart';

class Log {
  static final _env = DotEnv(includePlatformEnvironment: true, quiet: true)
    ..load();

  static bool get _isProd {
    final v = (_env['ENVIRONMENT'] ??
            Platform.environment['ENVIRONMENT'] ??
            'development')
        .trim()
        .toLowerCase();
    return v == 'production';
  }

  static void d(String message) {
    if (_isProd) return;
    // ignore: avoid_print
    print(message);
  }

  static void i(String message) {
    // ignore: avoid_print
    print(message);
  }

  static void w(String message) {
    // ignore: avoid_print
    print(message);
  }

  static void e(String message) {
    // ignore: avoid_print
    print(message);
  }
}
