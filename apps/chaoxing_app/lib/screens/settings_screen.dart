import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_config.dart';
import '../models/course_catalog.dart';
import '../services/local_sync_runner.dart';
import '../services/update_service.dart';

typedef ConfigSaver = Future<void> Function(AppConfig config);
typedef NotificationTester = Future<bool> Function(bool showDetails);
typedef VersionLabelLoader = Future<String> Function();
typedef CourseMonitoringChanged =
    Future<void> Function(String courseKey, bool monitored);
typedef AutostartEnabledLoader = Future<bool> Function();
typedef AutostartChanged = Future<void> Function(bool enabled);
typedef UpdateInfoLoader = Future<UpdateInfo?> Function();
typedef ReleasePageOpener = Future<void> Function(Uri uri);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.initialConfig,
    required this.onSave,
    this.onOpenLogin,
    this.onTestNotification,
    this.courseCatalog = CourseCatalog.empty,
    this.onCourseMonitoringChanged,
    this.onRefreshCourses,
    this.autostartEnabledLoader,
    this.onAutostartChanged,
    this.updateInfoLoader,
    this.onOpenReleasePage,
    this.versionLabelLoader = _loadVersionLabel,
    super.key,
  });

  final AppConfig initialConfig;
  final ConfigSaver onSave;
  final VoidCallback? onOpenLogin;
  final NotificationTester? onTestNotification;
  final CourseCatalog courseCatalog;
  final CourseMonitoringChanged? onCourseMonitoringChanged;
  final Future<void> Function()? onRefreshCourses;
  final AutostartEnabledLoader? autostartEnabledLoader;
  final AutostartChanged? onAutostartChanged;
  final UpdateInfoLoader? updateInfoLoader;
  final ReleasePageOpener? onOpenReleasePage;
  final VersionLabelLoader versionLabelLoader;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _cookieController;
  late final TextEditingController _pageLimitController;
  late final TextEditingController _itemLimitController;
  late final TextEditingController _courseLimitController;
  late double _refreshMinutes;
  late bool _remindersEnabled;
  late bool _showNotificationDetails;
  late bool _courseSourcesEnabled;
  late CourseCatalog _courseCatalog;
  late final Future<String> _versionLabel;
  Future<UpdateInfo?>? _updateInfo;
  bool _clearSavedCookie = false;
  bool _saving = false;
  bool _testingNotification = false;
  bool _refreshingCourses = false;
  bool? _autostartEnabled;
  bool _changingAutostart = false;

  @override
  void initState() {
    super.initState();
    _cookieController = TextEditingController();
    _pageLimitController = TextEditingController(
      text: widget.initialConfig.inboxPageLimit.toString(),
    );
    _itemLimitController = TextEditingController(
      text: widget.initialConfig.inboxItemLimit.toString(),
    );
    _courseLimitController = TextEditingController(
      text: widget.initialConfig.courseLimit.toString(),
    );
    _refreshMinutes = widget.initialConfig.refreshMinutes.toDouble();
    _remindersEnabled = widget.initialConfig.remindersEnabled;
    _showNotificationDetails = widget.initialConfig.showNotificationDetails;
    _courseSourcesEnabled = widget.initialConfig.courseSourcesEnabled;
    _courseCatalog = widget.courseCatalog;
    _versionLabel = widget.versionLabelLoader();
    _updateInfo = widget.updateInfoLoader?.call();
    _loadAutostartState();
  }

  Future<void> _loadAutostartState() async {
    final loader = widget.autostartEnabledLoader;
    if (loader == null) {
      return;
    }
    try {
      final enabled = await loader();
      if (mounted) {
        setState(() => _autostartEnabled = enabled);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _autostartEnabled = false);
      }
    }
  }

  @override
  void dispose() {
    _cookieController.dispose();
    _pageLimitController.dispose();
    _itemLimitController.dispose();
    _courseLimitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地同步设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.initialConfig.legacyWorkerConfigDetected) ...[
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('已检测到旧 Worker 配置'),
                subtitle: Text(
                  '当前版本改为本地同步。保存学习通 Cookie 后会清理旧 Worker URL 和 RUN_TOKEN。',
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            key: const ValueKey('cookie-input'),
            controller: _cookieController,
            onChanged: (value) {
              if (_clearSavedCookie && value.trim().isNotEmpty) {
                setState(() => _clearSavedCookie = false);
              }
            },
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '学习通 Cookie',
              helperText: '已保存 Cookie 时这里保持为空；只在输入新 Cookie 时覆盖。',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.cookie),
              border: OutlineInputBorder(),
            ),
          ),
          if (widget.initialConfig.isConfigured) ...[
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _clearSavedCookie
                    ? Icons.delete_outline
                    : Icons.check_circle_outline,
              ),
              title: Text(_clearSavedCookie ? '保存时将清除 Cookie' : '已保存 Cookie'),
              subtitle: const Text('不会在设置页回填完整 Cookie。'),
              trailing: TextButton(
                onPressed: () {
                  _cookieController.clear();
                  setState(() => _clearSavedCookie = !_clearSavedCookie);
                },
                child: Text(_clearSavedCookie ? '撤销' : '清除'),
              ),
            ),
          ],
          if (widget.onOpenLogin != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: widget.onOpenLogin,
              icon: const Icon(Icons.login),
              label: const Text('在 App 内重新登录'),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pageLimitController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '抓取页数',
                    prefixIcon: Icon(Icons.layers),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _itemLimitController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '抓取数量',
                    prefixIcon: Icon(Icons.format_list_numbered),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.school_outlined),
            title: const Text('课程空间补充同步'),
            subtitle: const Text('从课程空间补抓作业和考试，减少仅依赖收件箱造成的漏项。接口变化时可能出现部分失败。'),
            value: _courseSourcesEnabled,
            onChanged: (value) => setState(() => _courseSourcesEnabled = value),
          ),
          if (_courseSourcesEnabled) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _courseLimitController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '最多扫描课程数',
                prefixIcon: Icon(Icons.format_list_numbered),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '已监控 ${_courseCatalog.monitoredCourses.length} / '
              '${_courseCatalog.courses.length} 门课程',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (widget.onRefreshCourses != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _refreshingCourses
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setState(() => _refreshingCourses = true);
                          try {
                            await widget.onRefreshCourses!();
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('课程列表已刷新')),
                              );
                            }
                          } catch (_) {
                            if (mounted) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('课程列表刷新失败')),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _refreshingCourses = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.refresh),
                  label: Text(_refreshingCourses ? '刷新中' : '刷新课程列表'),
                ),
              ),
            for (final preference in _courseCatalog.courses)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(preference.course.title),
                subtitle: Text(
                  '课程 ${preference.course.courseId} · '
                  '班级 ${preference.course.classId}',
                ),
                value: preference.monitored,
                onChanged: widget.onCourseMonitoringChanged == null
                    ? null
                    : (value) async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await widget.onCourseMonitoringChanged!(
                            preference.course.key,
                            value,
                          );
                          if (mounted) {
                            setState(() {
                              _courseCatalog = _courseCatalog.setMonitored(
                                preference.course.key,
                                value,
                              );
                            });
                          }
                        } catch (_) {
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('课程监控设置保存失败')),
                            );
                          }
                        }
                      },
              ),
          ],
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Windows 截止提醒'),
            subtitle: const Text('在截止前 72 小时内发送一次系统通知，并记录去重历史。'),
            value: _remindersEnabled,
            onChanged: (value) => setState(() => _remindersEnabled = value),
          ),
          if (_remindersEnabled)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.visibility_outlined),
              title: const Text('在系统通知中显示任务详情'),
              subtitle: const Text('关闭后，锁屏和通知中心只显示通用提醒；点击后仍可在 App 内查看详情。'),
              value: _showNotificationDetails,
              onChanged: (value) =>
                  setState(() => _showNotificationDetails = value),
            ),
          if (widget.onTestNotification != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _testingNotification
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _testingNotification = true);
                      try {
                        final delivered = await widget.onTestNotification!(
                          _showNotificationDetails,
                        );
                        if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                delivered
                                    ? '测试通知已发送；点击通知应恢复主窗口'
                                    : '当前平台或通知服务不可用',
                              ),
                            ),
                          );
                        }
                      } catch (_) {
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('测试通知发送失败，请检查 Windows 通知设置'),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _testingNotification = false);
                        }
                      }
                    },
              icon: const Icon(Icons.notification_add_outlined),
              label: Text(_testingNotification ? '发送中' : '发送测试通知'),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '自动刷新间隔：${_refreshMinutes.round()} 分钟',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Slider(
            value: _refreshMinutes,
            min: 15,
            max: 180,
            divisions: 11,
            label: '${_refreshMinutes.round()} 分钟',
            onChanged: (value) => setState(() => _refreshMinutes = value),
          ),
          const SizedBox(height: 12),
          if (widget.autostartEnabledLoader != null &&
              widget.onAutostartChanged != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.power_settings_new),
              title: const Text('开机自启'),
              subtitle: const Text('登录 Windows 后在后台启动，可从系统托盘打开。'),
              value: _autostartEnabled ?? false,
              onChanged: _autostartEnabled == null || _changingAutostart
                  ? null
                  : (value) async {
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _changingAutostart = true);
                      try {
                        await widget.onAutostartChanged!(value);
                        if (mounted) {
                          setState(() => _autostartEnabled = value);
                        }
                      } catch (_) {
                        if (mounted) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('开机自启设置失败')),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _changingAutostart = false);
                        }
                      }
                    },
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _saving = true);
                    final enteredCookie = _cookieController.text.trim();
                    final nextCookie = enteredCookie.isNotEmpty
                        ? enteredCookie
                        : _clearSavedCookie
                        ? ''
                        : widget.initialConfig.cookie;
                    try {
                      await widget.onSave(
                        AppConfig(
                          cookie: nextCookie,
                          inboxPageLimit: _readPositiveInt(
                            _pageLimitController.text,
                            3,
                            maximum: 20,
                          ),
                          inboxItemLimit: _readPositiveInt(
                            _itemLimitController.text,
                            60,
                            maximum: 500,
                          ),
                          refreshMinutes: _refreshMinutes.round(),
                          remindersEnabled: _remindersEnabled,
                          showNotificationDetails: _showNotificationDetails,
                          courseSourcesEnabled: _courseSourcesEnabled,
                          courseLimit: _readPositiveInt(
                            _courseLimitController.text,
                            20,
                            maximum: 100,
                          ),
                        ),
                      );
                      _cookieController.clear();
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('设置已保存')),
                        );
                      }
                    } catch (error) {
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              error is LocalSyncException
                                  ? error.message
                                  : '设置保存失败，请稍后重试',
                            ),
                          ),
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _saving = false);
                      }
                    }
                  },
            icon: const Icon(Icons.save),
            label: Text(_saving ? '保存中' : '保存并同步'),
          ),
          const SizedBox(height: 16),
          if (_updateInfo != null)
            FutureBuilder<UpdateInfo?>(
              future: _updateInfo,
              builder: (context, snapshot) {
                final update = snapshot.data;
                if (update == null) {
                  return const SizedBox.shrink();
                }
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.system_update_alt),
                    title: Text('发现新版本（构建 ${update.buildNumber}）'),
                    subtitle: const Text('仅提示更新，不会自动下载、安装或重启。'),
                    trailing: TextButton(
                      onPressed: widget.onOpenReleasePage == null
                          ? null
                          : () => widget.onOpenReleasePage!(update.releasePage),
                      child: const Text('查看发布页'),
                    ),
                  ),
                );
              },
            ),
          if (_updateInfo != null) const SizedBox(height: 12),
          FutureBuilder<String>(
            future: _versionLabel,
            builder: (context, snapshot) {
              final label = snapshot.hasError
                  ? '版本信息不可用'
                  : snapshot.data ?? '版本信息加载中';
              return Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<String> _loadVersionLabel() async {
  final info = await PackageInfo.fromPlatform();
  final buildNumber = info.buildNumber.trim();
  return buildNumber.isEmpty
      ? '版本 ${info.version}'
      : '版本 ${info.version}（构建 $buildNumber）';
}

int _readPositiveInt(String value, int fallback, {required int maximum}) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed < 1) {
    return fallback;
  }
  return parsed > maximum ? maximum : parsed;
}
