import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/main.dart';
import 'package:inlink/core/network/fake_network_transport.dart';

void main() {
  testWidgets('shows InLink foundation status', (tester) async {
    await tester.pumpWidget(
      InLinkApp(transport: FakeNetworkTransport()),
    );

    expect(find.text('InLink'), findsOneWidget);
    expect(find.text('Network status'), findsOneWidget);
    expect(find.text('Check network capabilities'), findsOneWidget);
  });
}
