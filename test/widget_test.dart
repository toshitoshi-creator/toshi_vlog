import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:toshi_vlog/main.dart';

void main() {
  testWidgets('shows camera, highlights, edit, and media tabs', (
    WidgetTester tester,
  ) async {
    // The default test surface is landscape-shaped (800x600); use a
    // portrait size so the bottom nav bar (hidden by default in landscape)
    // renders as it would on a phone held upright.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ToshiVlogApp());
    await tester.pump();

    expect(find.text('カメラ'), findsOneWidget);
    expect(find.text('まとめ'), findsOneWidget);
    expect(find.text('編集'), findsOneWidget);
    expect(find.text('メディア'), findsOneWidget);
  });
}
