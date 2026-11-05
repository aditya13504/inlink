import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/security/replay_protection_store.dart';

void main() {
  test('replay identifier is stable for the same envelope', () async {
    final store = ReplayProtectionStore();
    final first = await store.identifierForEnvelope('test-envelope');
    final second = await store.identifierForEnvelope('test-envelope');
    expect(first, second);
    expect(first, isNotEmpty);
  });

  test('different envelope bytes produce different identifiers', () async {
    final store = ReplayProtectionStore();
    final first = await store.identifierForEnvelope('envelope-a');
    final second = await store.identifierForEnvelope('envelope-b');
    expect(first, isNot(second));
  });
}
