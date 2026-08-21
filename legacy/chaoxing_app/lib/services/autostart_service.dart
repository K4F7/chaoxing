import 'dart:io';

const hiddenLaunchArgument = '--hidden';
const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
const _valueName = 'ChaoxingTodo';

bool isHiddenLaunch(List<String> arguments) =>
    arguments.contains(hiddenLaunchArgument);

abstract class AutostartStore {
  Future<String?> readCommand();

  Future<void> writeCommand(String command);

  Future<void> removeCommand();
}

class WindowsRegistryAutostartStore implements AutostartStore {
  const WindowsRegistryAutostartStore();

  @override
  Future<String?> readCommand() async {
    final result = await Process.run('reg', [
      'query',
      _runKey,
      '/v',
      _valueName,
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    final match = RegExp(
      r'ChaoxingTodo\s+REG_SZ\s+(.+)$',
      multiLine: true,
    ).firstMatch(result.stdout.toString());
    return match?.group(1)?.trim();
  }

  @override
  Future<void> writeCommand(String command) async {
    final result = await Process.run('reg', [
      'add',
      _runKey,
      '/v',
      _valueName,
      '/t',
      'REG_SZ',
      '/d',
      command,
      '/f',
    ]);
    if (result.exitCode != 0) {
      throw StateError('开机自启注册失败');
    }
  }

  @override
  Future<void> removeCommand() async {
    final result = await Process.run('reg', [
      'delete',
      _runKey,
      '/v',
      _valueName,
      '/f',
    ]);
    if (result.exitCode != 0 && await readCommand() != null) {
      throw StateError('开机自启移除失败');
    }
  }
}

class MemoryAutostartStore implements AutostartStore {
  String? command;

  @override
  Future<String?> readCommand() async => command;

  @override
  Future<void> writeCommand(String command) async {
    this.command = command;
  }

  @override
  Future<void> removeCommand() async {
    command = null;
  }
}

class AutostartService {
  AutostartService({
    AutostartStore? store,
    String? executablePath,
    bool? supported,
  }) : _store = store ?? const WindowsRegistryAutostartStore(),
       _executablePath = executablePath ?? Platform.resolvedExecutable,
       _supported = supported ?? Platform.isWindows;

  final AutostartStore _store;
  final String _executablePath;
  final bool _supported;

  String get expectedCommand => '"$_executablePath" $hiddenLaunchArgument';

  Future<bool> isEnabled() async {
    if (!_supported) {
      return false;
    }
    return await _store.readCommand() == expectedCommand;
  }

  Future<void> setEnabled(bool enabled) async {
    if (!_supported) {
      throw UnsupportedError('当前平台不支持开机自启');
    }
    if (enabled) {
      await _store.writeCommand(expectedCommand);
    } else {
      await _store.removeCommand();
    }
  }
}
