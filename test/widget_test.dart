import 'package:flutter_test/flutter_test.dart';

import 'package:toshi_vlog/main.dart';

void main() {
  testWidgets('shows camera and list tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const ToshiVlogApp());
    await tester.pump();

    expect(find.text('カメラ'), findsOneWidget);
    expect(find.text('一覧'), findsOneWidget);
  });
}
