import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talaria_flutter/talaria_flutter.dart';

void main() {
  testWidgets('TalariaScreenCapture is idle before init', (tester) async {
    await tester.pumpWidget(
      const TalariaScreenCapture(child: SizedBox.shrink()),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
