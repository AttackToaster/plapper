// UI-only smoke test. The full app is not pumped here because it loads the
// native plounter core via FFI, which is not available in the test runner.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plounter/main.dart';

void main() {
  testWidgets('level meter renders without a native library', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: LevelMeter(envelopeDb: -30, floorDb: -60, thresholdDb: -48),
      ),
    ));
    expect(find.byType(LevelMeter), findsOneWidget);
  });
}
