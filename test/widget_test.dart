import 'package:flutter_test/flutter_test.dart';

import 'package:taxicab_viewer/main.dart';

void main() {
  testWidgets('App arranca y muestra el WebView', (WidgetTester tester) async {
    await tester.pumpWidget(const TaxiCabViewerApp());
    await tester.pump();

    expect(find.byType(TaxiCabViewerApp), findsOneWidget);
  });
}
