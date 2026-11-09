@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Web apps ship minified dart2js output. A capture path that compiles to
/// JavaScript referencing an undeclared name throws on every event, so this
/// compiles a capture program the way `flutter build web --release` does and
/// runs it under Node.
void main() {
  final node = _which('node');

  for (final level in ['-O2', '-O4']) {
    test(
      'captureMessage and captureException enqueue under dart2js $level',
      () async {
        final out = await Directory.systemTemp.createTemp('talaria_dart2js');
        addTearDown(() => out.delete(recursive: true));
        final js = '${out.path}/capture.js';
        final compile = await Process.run(Platform.resolvedExecutable, [
          'compile',
          'js',
          level,
          '-o',
          js,
          'test/fixtures/dart2js_capture_main.dart',
        ]);
        expect(compile.exitCode, 0,
            reason: '${compile.stdout}${compile.stderr}');

        final run = await Process.start(node!, [
          '-e',
          'globalThis.self = globalThis; require(process.argv[1]);',
          js,
        ]);
        final lines = <String>[];
        final done = Completer<void>();
        run.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          lines.add(line);
          if (line == 'CAPTURE DONE' && !done.isCompleted) done.complete();
        });
        run.stderr.transform(utf8.decoder).listen(lines.add);
        // The client keeps flush timers alive; stop once the program reports.
        await done.future
            .timeout(const Duration(seconds: 30), onTimeout: () {});
        run.kill();

        expect(
            lines, containsAll(['CAPTURE message OK', 'CAPTURE exception OK']),
            reason: lines.join('\n'));
      },
      skip: node == null ? 'node is not on PATH' : false,
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}

String? _which(String name) {
  for (final dir in (Platform.environment['PATH'] ?? '').split(':')) {
    final file = File('$dir/$name');
    if (file.existsSync()) return file.path;
  }
  return null;
}
