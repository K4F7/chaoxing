import 'package:chaoxing_app/services/autostart_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes only the explicit hidden launch argument', () {
    expect(isHiddenLaunch(['--hidden']), isTrue);
    expect(isHiddenLaunch(['--other']), isFalse);
  });

  test('registers and removes a hidden per-user startup command', () async {
    final store = MemoryAutostartStore();
    final service = AutostartService(
      store: store,
      executablePath: r'C:\Program Files\Chaoxing\chaoxing_app.exe',
      supported: true,
    );

    expect(await service.isEnabled(), isFalse);
    await service.setEnabled(true);
    expect(
      store.command,
      r'"C:\Program Files\Chaoxing\chaoxing_app.exe" --hidden',
    );
    expect(await service.isEnabled(), isTrue);

    await service.setEnabled(false);
    expect(store.command, isNull);
    expect(await service.isEnabled(), isFalse);
  });
}
