import 'package:stack_trace/stack_trace.dart' as st;

/// Builds Serverpod `StackFrameDto` wire maps from Dart stack traces.
class StackFrameBuilder {
  StackFrameBuilder._();

  static const String platform = 'dart';

  /// Frames oldest → newest from a [StackTrace].
  static List<Map<String, Object?>> framesFromStackTrace(
    StackTrace? stackTrace, {
    String framePlatform = platform,
  }) {
    if (stackTrace == null) {
      return const [];
    }
    try {
      final trace = st.Trace.from(stackTrace);
      // Trace.frames is outermost (caller) first in stack_trace package —
      // reverse so oldest → newest matches PHP/server convention.
      final frames = trace.frames.reversed.toList();
      return [
        for (final frame in frames) fromTraceFrame(frame, framePlatform),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Map<String, Object?> fromTraceFrame(
    st.Frame frame,
    String framePlatform,
  ) {
    final wire = <String, Object?>{
      '__className__': 'StackFrameDto',
      'platform': framePlatform,
      'inApp': isInApp(frame.uri.toString()),
    };

    final uri = frame.uri.toString();
    if (uri.isNotEmpty) {
      wire['absPath'] = uri;
      wire['filename'] = _basename(uri);
      if (uri.startsWith('package:')) {
        final package = _packageName(uri);
        if (package != null) {
          wire['package'] = package;
          wire['module'] = package;
        }
      }
    }

    final member = frame.member;
    if (member != null && member.isNotEmpty) {
      wire['functionName'] = member;
    }

    if (frame.line != null) {
      wire['lineno'] = frame.line;
    }
    if (frame.column != null) {
      wire['colno'] = frame.column;
    }

    return wire;
  }

  static const Set<String> _deniedPackages = {
    'serverpod',
    'relic',
    'relic_core',
    'relic_io',
    'talaria',
    'talaria_flutter',
    'talaria_serverpod',
  };

  static bool isInApp(String path) {
    if (path.startsWith('dart:') || path.startsWith('package:flutter/')) {
      return false;
    }
    if (path.contains('/.pub-cache/') || path.contains('/flutter/packages/')) {
      return false;
    }
    if (path.startsWith('package:')) {
      final package = _packageName(path);
      if (package != null && _isDeniedPackage(package)) {
        return false;
      }
      return true;
    }
    return path.startsWith('file:');
  }

  static bool _isDeniedPackage(String package) {
    if (_deniedPackages.contains(package)) {
      return true;
    }
    return package.startsWith('serverpod_') || package.startsWith('relic_');
  }

  static String _basename(String path) {
    final slash = path.lastIndexOf('/');
    return slash == -1 ? path : path.substring(slash + 1);
  }

  static String? _packageName(String uri) {
    // package:foo/bar.dart → foo
    if (!uri.startsWith('package:')) {
      return null;
    }
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) {
      return rest.isEmpty ? null : rest;
    }
    return rest.substring(0, slash);
  }
}
