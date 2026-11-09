// Compiled by test/dart2js_capture_test.dart with minified dart2js.
// Keeps beforeSend and processors live (as an app build does) so the capture
// path is compiled in full.
import 'package:talaria/talaria.dart';

Future<void> main() async {
  final client = TalariaClient(
    TalariaOptions(
      url: 'http://127.0.0.1:9',
      apiKey:
          'tal_sk_test_nz1_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg3B299S',
      beforeSend: DateTime.now().year > 3000 ? (event, hint) => event : null,
    ),
  );
  client.addProcessor((bag) => bag);
  final captures = <String, Future<void> Function()>{
    'message': () =>
        client.captureMessage('dart2js message', level: SeverityLevel.warning),
    'exception': () => client.captureException(
          StateError('dart2js exception'),
          stackTrace: StackTrace.current,
        ),
  };
  for (final entry in captures.entries) {
    try {
      await entry.value();
      print('CAPTURE ${entry.key} OK');
    } catch (e) {
      print('CAPTURE ${entry.key} FAILED $e');
    }
  }
  print('CAPTURE DONE');
}
