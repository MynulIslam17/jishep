import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:gps_cielo/core/config/app_config.dart';
import 'package:logger/logger.dart';

/// Prints every backend call in debug builds (Firestore, Auth, HTTP, geocoding).
///
/// Turn off with [AppConfig.logApiOperations] or by running a release build.
class ApiDebugLog {
  ApiDebugLog._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 3,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.none,
    ),
  );

  static bool get enabled => kDebugMode && AppConfig.logApiOperations;

  /// Runs [action] and logs start, success (with duration), or failure.
  static Future<T> run<T>(
    String operation,
    Future<T> Function() action, {
    Object? details,
  }) async {
    if (!enabled) return action();

    final sw = Stopwatch()..start();
    _logger.d('API → $operation${_suffix(details)}');
    try {
      final result = await action();
      _logger.d(
        'API ✓ $operation ${sw.elapsedMilliseconds}ms${_resultSuffix(result)}',
      );
      return result;
    } catch (error, stack) {
      _logger.e(
        'API ✗ $operation ${sw.elapsedMilliseconds}ms',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  /// Logs when a Firestore (or other) stream emits or errors.
  static Stream<T> stream<T>(
    String operation,
    Stream<T> source, {
    Object? details,
  }) {
    if (!enabled) return source;

    _logger.d('API ⟳ listen $operation${_suffix(details)}');
    return Stream<T>.multi((controller) {
      late final StreamSubscription<T> subscription;
      subscription = source.listen(
        (event) {
          _logger.d('API ⟳ $operation${_resultSuffix(event)}');
          controller.add(event);
        },
        onError: (Object error, StackTrace stack) {
          _logger.e(
            'API ✗ stream $operation',
            error: error,
            stackTrace: stack,
          );
          controller.addError(error, stack);
        },
        onDone: controller.close,
      );
      controller
        ..onPause = subscription.pause
        ..onResume = subscription.resume
        ..onCancel = subscription.cancel;
    });
  }

  static String _suffix(Object? details) {
    if (details == null) return '';
    return '  $details';
  }

  static String _resultSuffix(Object? result) {
    if (result == null) return '  null';
    if (result is Iterable) return '  ${result.length} items';
    if (result is Map) return '  ${result.length} keys';
    return '  ${result.runtimeType}';
  }
}
