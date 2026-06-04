import 'package:flutter/material.dart';

import '../models/app_config.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.initialConfig,
    required this.onSave,
    super.key,
  });

  final AppConfig initialConfig;
  final ValueChanged<AppConfig> onSave;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _tokenController;
  late double _refreshMinutes;

  @override
  void initState() {
    super.initState();
    _baseUrlController = TextEditingController(
      text: widget.initialConfig.baseUrl,
    );
    _tokenController = TextEditingController(text: widget.initialConfig.token);
    _refreshMinutes = widget.initialConfig.refreshMinutes.toDouble();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('连接设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _baseUrlController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Worker URL',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _tokenController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'RUN_TOKEN',
              prefixIcon: Icon(Icons.key),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '刷新间隔：${_refreshMinutes.round()} 分钟',
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
            onPressed: () {
              widget.onSave(
                AppConfig(
                  baseUrl: _baseUrlController.text,
                  token: _tokenController.text,
                  refreshMinutes: _refreshMinutes.round(),
                ),
              );
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.save),
            label: const Text('保存并同步'),
          ),
        ],
      ),
    );
  }
}
