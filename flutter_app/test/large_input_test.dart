import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gps_track_desktop/ui/analyzer_controller.dart';
import 'package:gps_track_desktop/ui/widgets.dart';

void main() {
  test('multi-megabyte paste keeps full source and bounded preview', () {
    final controller = ProtocolTextController(previewLimit: 16000);
    addTearDown(controller.dispose);
    final source = List<String>.filled(28000, '告警类型:震动报警(003)').join('\n');

    // 模拟 EditableText 在 Ctrl+V / Win+V 后写入 controller.value。
    controller.value = TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: source.length),
    );

    expect(controller.isPreviewing, isTrue);
    expect(controller.sourceText, same(source));
    expect(controller.sourceLength, source.length);
    expect(controller.sourceLineCount, 28000);
    expect(controller.text.length, 16000);
    expect(controller.text, isNot(contains('大文本预览结束')));
  });

  test('loads exactly one additional preview page and preserves selection', () {
    final controller = ProtocolTextController(previewLimit: 16000);
    addTearDown(controller.dispose);
    final source = List<String>.filled(40000, 'X').join();
    controller.setSource(source);
    controller.selection = const TextSelection.collapsed(offset: 1234);

    expect(controller.visibleLength, 16000);
    expect(controller.hasMorePreview, isTrue);
    expect(controller.loadNextPreviewPage(), isTrue);
    expect(controller.visibleLength, 32000);
    expect(controller.selection.baseOffset, 1234);
    expect(controller.sourceText, same(source));

    expect(controller.loadNextPreviewPage(), isTrue);
    expect(controller.visibleLength, 40000);
    expect(controller.hasMorePreview, isFalse);
    expect(controller.loadNextPreviewPage(), isFalse);
  });

  testWidgets('large preview renders without laying out full source', (
    tester,
  ) async {
    final controller = ProtocolTextController(previewLimit: 16000);
    addTearDown(controller.dispose);
    final source = List<String>.filled(28000, '定位状态:已定位').join('\n');
    controller.setSource(source);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            readOnly: controller.isPreviewing,
            maxLines: 20,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(controller.text.length, 16000);
    expect(controller.text, isNot(contains('大文本预览结束')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling to the bottom appends only one 16000 character page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final analyzer = AnalyzerController();
    addTearDown(analyzer.dispose);
    analyzer.setSource(List<String>.filled(12000, 'packet line').join('\n'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 350, child: InputSidebar(controller: analyzer)),
        ),
      ),
    );
    await tester.pump();

    final editorScrollable = find.descendant(
      of: find.byType(EditableText),
      matching: find.byType(Scrollable),
    );
    expect(editorScrollable, findsOneWidget);
    final scrollable = tester.state<ScrollableState>(editorScrollable);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    await tester.pump();

    expect(analyzer.source.visibleLength, 32000);
    expect(analyzer.source.sourceText.length, greaterThan(32000));
    expect(find.textContaining('32000/'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('editing a bounded preview preserves its hidden full-source tail', () {
    final controller = ProtocolTextController(previewLimit: 8);
    addTearDown(controller.dispose);
    controller.setSource('0123456789ABCDEF');
    controller.value = const TextEditingValue(
      text: 'X01234567',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(controller.sourceText, 'X0123456789ABCDEF');
    expect(controller.text, 'X0123456');
  });

  test('select-all paste replaces a previously previewed full source', () {
    final controller = ProtocolTextController(previewLimit: 8);
    addTearDown(controller.dispose);
    controller.setSource('OLD-DATA-HIDDEN-TAIL');
    controller.value = const TextEditingValue(
      text: 'NEW-DATA-IS-LONG',
      selection: TextSelection.collapsed(offset: 16),
    );
    expect(controller.sourceText, 'NEW-DATA-IS-LONG');
    expect(controller.text, 'NEW-DATA');
  });
}
