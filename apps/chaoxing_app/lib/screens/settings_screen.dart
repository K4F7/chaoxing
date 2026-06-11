import 'package:flutter/material.dart';

import '../models/app_config.dart';

typedef ConfigSaver = Future<void> Function(AppConfig config);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.initialConfig,
    required this.onSave,
    super.key,
  });

  final AppConfig initialConfig;
  final ConfigSaver onSave;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _cookieController;
  late final TextEditingController _pageLimitController;
  late final TextEditingController _itemLimitController;
  late double _refreshMinutes;
  late bool _remindersEnabled;
  bool _saving = false;

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
    _refreshMinutes = widget.initialConfig.refreshMinutes.toDouble();
    _remindersEnabled = widget.initialConfig.remindersEnabled;
  }

  @override
  void dispose() {
    _cookieController.dispose();
    _pageLimitController.dispose();
    _itemLimitController.dispose();
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
            controller: _cookieController,
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
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.check_circle_outline),
              title: Text('已保存 Cookie'),
              subtitle: Text('不会在设置页回填完整 Cookie。'),
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
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('提醒去重'),
            subtitle: const Text('记录已提醒项目；Windows 系统通知仍待接入。'),
            value: _remindersEnabled,
            onChanged: (value) => setState(() => _remindersEnabled = value),
          ),
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
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _saving = true);
                    final nextCookie = _cookieController.text.trim().isEmpty
                        ? widget.initialConfig.cookie
                        : _cookieController.text;
                    try {
                      await widget.onSave(
                        AppConfig(
                          cookie: nextCookie,
                          inboxPageLimit: _readPositiveInt(
                            _pageLimitController.text,
                            3,
                          ),
                          inboxItemLimit: _readPositiveInt(
                            _itemLimitController.text,
                            60,
                          ),
                          refreshMinutes: _refreshMinutes.round(),
                          remindersEnabled: _remindersEnabled,
                        ),
                      );
                      _cookieController.clear();
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(content: Text('设置已保存')),
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
        ],
      ),
    );
  }
}

int _readPositiveInt(String value, int fallback) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || parsed < 1) {
    return fallback;
  }
  return parsed;
}
