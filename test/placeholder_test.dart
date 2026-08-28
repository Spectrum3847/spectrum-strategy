import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/main.dart';

void main() {
  testWidgets('the placeholder says where the real source is', (tester) async {
    await tester.pumpWidget(const PlaceholderApp());

    expect(find.textContaining('release 1.0.0'), findsOneWidget);
  });
}
