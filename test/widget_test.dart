import 'package:flutter_test/flutter_test.dart';

import 'package:toshi_vlog/main.dart';

void main() {
  testWidgets('shows camera, highlights, and media tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ToshiVlogApp());
    await tester.pump();

    expect(find.text('カメラ'), findsOneWidget);
    expect(find.text('まとめ'), findsOneWidget);
    expect(find.text('メディア'), findsOneWidget);
  });
}
