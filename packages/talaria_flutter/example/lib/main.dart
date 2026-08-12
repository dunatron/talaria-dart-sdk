import 'package:flutter/material.dart';
import 'package:talaria_flutter/talaria_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await TalariaFlutter.init(
    TalariaOptions(
      dsn: const String.fromEnvironment(
        'TALARIA_DSN',
        defaultValue: 'https://api.newtalaria.com',
      ),
      apiKey: const String.fromEnvironment(
        'TALARIA_API_KEY',
        defaultValue: 'tal_live_replace_me',
      ),
      environment: const String.fromEnvironment(
        'APP_ENV',
        defaultValue: 'development',
      ),
      release: const String.fromEnvironment(
        'APP_RELEASE',
        defaultValue: '0.1.0+example',
      ),
      minLevel: SeverityLevel.info,
      defaultIntegrations: false,
    ),
  );

  ErrorWidget.builder = talariaErrorWidgetBuilder();

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Talaria Flutter Example',
      navigatorObservers: [TalariaNavigatorObserver()],
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Talaria example')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: () async {
                await Talaria.logger(tags: {'screen': 'home'})
                    .warn('Example warning from button');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Warned Talaria')),
                  );
                }
              },
              child: const Text('Capture warning'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () async {
                try {
                  throw StateError('Example exception');
                } catch (e, st) {
                  await Talaria.captureException(
                    e,
                    stackTrace: st,
                    context: const CaptureContext(
                      tags: {'area': 'example'},
                    ),
                  );
                }
              },
              child: const Text('Capture exception'),
            ),
          ],
        ),
      ),
    );
  }
}
