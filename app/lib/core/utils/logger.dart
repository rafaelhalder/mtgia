import 'package:flutter/foundation.dart';

/// Logger centralizado que só exibe logs em modo debug/development.
/// Em produção (release mode), os logs são silenciados.
class AppLogger {
  /// Log apenas em modo debug (kDebugMode)
  static void debug(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  /// Log de erro - sempre exibe (útil para tracking)
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('❌ ERROR: $message');
      if (error != null) debugPrint('  -> $error');
      if (stackTrace != null) debugPrint('  -> $stackTrace');
    }
    // Em produção, poderia enviar para serviço de crash reporting
  }

  /// Log de warning
  static void warning(String message) {
    if (kDebugMode) {
      debugPrint('⚠️ WARNING: $message');
    }
  }

  /// Log de info
  static void info(String message) {
    if (kDebugMode) {
      debugPrint('ℹ️ $message');
    }
  }
}
