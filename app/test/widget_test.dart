// UI-only smoke test. The full app is not pumped here because it loads the
// native plapper core via FFI, which is not available in the test runner.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:plapper/main.dart';

void main() {
  testWidgets('envelope graph renders without a native library',
      (tester) async {
    final hist = List<double>.filled(120, -80.0);
    hist[60] = -30.0; // one clap spike
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EnvelopeGraph(
          history: hist,
          head: 0,
          floorDb: -70,
          thresholdDb: -58,
        ),
      ),
    ));
    expect(find.byType(EnvelopeGraph), findsOneWidget);
  });
}
