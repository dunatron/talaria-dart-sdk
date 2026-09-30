import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talaria_flutter/src/heatmaps/heatmap_tree.dart';
import 'package:talaria_flutter/src/heatmaps/markers.dart';
import 'package:talaria_flutter/src/heatmaps/privacy.dart';

void main() {
  testWidgets('names buttons and fields from their labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Text('Overview'),
              FilledButton(onPressed: () {}, child: const Text('Save')),
              const TextField(
                decoration: InputDecoration(labelText: 'Email'),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: () {},
                icon: const Icon(Icons.settings),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final root = tester.element(find.byType(Scaffold));
    final boundary = tester.renderObject<RenderBox>(find.byType(Scaffold));
    final tree = collectHeatmapTree(root, boundary);
    final paths = tree.nodes.map((node) => node.path).toList();

    expect(paths, contains('button:Save'));
    expect(paths, contains('text:Overview'));
    expect(paths, contains('textField:Email'));
    expect(paths, contains('button:Settings'));
    expect(paths.any((path) => path.contains('node:0')), isFalse);
    expect(paths.any((path) => path.contains('/')), isFalse);

    final save = tree.nodes.firstWhere((node) => node.path == 'button:Save');
    expect(tree.hit(save.globalRect.center)?.path, 'button:Save');
  });

  testWidgets('input covers follow privacy and passwords stay covered', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Text('Hello'),
              TextField(decoration: InputDecoration(labelText: 'Email')),
              TextField(
                obscureText: true,
                decoration: InputDecoration(labelText: 'Password'),
              ),
              TalariaMask(
                  child:
                      SizedBox(width: 80, height: 40, child: Text('Secret'))),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final root = tester.element(find.byType(Scaffold));
    final boundary = tester.renderObject<RenderBox>(find.byType(Scaffold));

    final open = heatmapCoverRects(
      root: root,
      boundary: boundary,
      ratio: 1,
      privacy: const TalariaHeatmapPrivacy(),
    );
    expect(open.covers, isNotEmpty);
    final email = tester.getRect(find.byType(EditableText).first);
    final password = tester.getRect(find.byType(EditableText).last);
    expect(open.covers.any((rect) => rect.overlaps(email)), isFalse);
    expect(open.covers.any((rect) => rect.overlaps(password)), isTrue);

    final masked = heatmapCoverRects(
      root: root,
      boundary: boundary,
      ratio: 1,
      privacy: const TalariaHeatmapPrivacy(maskInputs: true, maskText: true),
    );
    expect(masked.covers.any((rect) => rect.overlaps(email)), isTrue);
    expect(
      masked.covers
          .any((rect) => rect.overlaps(tester.getRect(find.text('Hello')))),
      isTrue,
    );
  });
}
