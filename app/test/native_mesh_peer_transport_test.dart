import 'package:flutter_test/flutter_test.dart';
import 'package:inlink/core/network/mesh/native_mesh_peer_transport.dart';

const nodeA = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const nodeB = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';

void main() {
  test('directory binds authenticated node IDs to BLE transport addresses', () {
    final directory = VerifiedBlePeerDirectory();
    directory.bindAfterAuthentication(nodeId: nodeA, bleAddress: 'AA:BB:CC:DD:EE:FF');
    expect(directory.addressFor(nodeA), 'AA:BB:CC:DD:EE:FF');
    expect(directory.nodeForAddress('aa:bb:cc:dd:ee:ff'), nodeA);
  });

  test('directory refuses malformed node IDs and addresses', () {
    final directory = VerifiedBlePeerDirectory();
    expect(
      () => directory.bindAfterAuthentication(nodeId: 'bad', bleAddress: 'AA:BB:CC:DD:EE:FF'),
      throwsArgumentError,
    );
    expect(
      () => directory.bindAfterAuthentication(nodeId: nodeA, bleAddress: 'not-a-device'),
      throwsArgumentError,
    );
  });

  test('one BLE address cannot impersonate two different node IDs', () {
    final directory = VerifiedBlePeerDirectory();
    directory.bindAfterAuthentication(nodeId: nodeA, bleAddress: 'AA:BB:CC:DD:EE:FF');
    expect(
      () => directory.bindAfterAuthentication(nodeId: nodeB, bleAddress: 'aa:bb:cc:dd:ee:ff'),
      throwsStateError,
    );
  });
}
