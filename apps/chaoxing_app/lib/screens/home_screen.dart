import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/sync_item.dart';
import '../services/local_diagnostics.dart';
import '../state/app_controller.dart';
import '../widgets/month_calendar.dart';
import '../widgets/sync_item_card.dart';
import 'detail_screen.dart';
import 'diagnostics_screen.dart';
import 'settings_screen.dart';
import 'windows_login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.controller, super.key});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    widget.controller.load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习通待办'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: controller.refreshing || !controller.isConfigured
                ? null
                : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '诊断',
            onPressed: () => _openDiagnostics(context),
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: () => _openSettings(context),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : controller.isConfigured
          ? _Dashboard(
              controller: controller,
              tabIndex: _tabIndex,
              onTabChanged: (value) => setState(() => _tabIndex = value),
              onItemTap: (item) => _openDetail(context, item),
              onOpenDiagnostics: () => _openDiagnostics(context),
            )
          : _EmptySetup(
              onOpenLogin: Platform.isWindows
                  ? () => _openLogin(context)
                  : null,
              onOpenSettings: () => _openSettings(context),
            ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          initialConfig: widget.controller.config,
          onSave: widget.controller.saveConfig,
          onTestNotification: Platform.isWindows
              ? widget.controller.sendTestNotification
              : null,
          onOpenLogin: Platform.isWindows
              ? () {
                  Navigator.of(context).pop();
                  _openLogin(context);
                }
              : null,
        ),
      ),
    );
  }

  void _openLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WindowsLoginScreen(
          onCookieCaptured: widget.controller.importLoginCookie,
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, SyncItem item) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => DetailScreen(item: item)));
  }

  void _openDiagnostics(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiagnosticsScreen(
          sync: widget.controller.sync,
          error: widget.controller.error,
          onCopyDiagnostics: () async {
            final report = buildDiagnosticsReport(
              cookieHeader: widget.controller.config.cookie,
              sync: widget.controller.sync,
              lastError: widget.controller.error,
            );
            await Clipboard.setData(ClipboardData(text: report));
          },
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.controller,
    required this.tabIndex,
    required this.onTabChanged,
    required this.onItemTap,
    required this.onOpenDiagnostics,
  });

  final AppController controller;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<SyncItem> onItemTap;
  final VoidCallback onOpenDiagnostics;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SummaryHeader(controller: controller),
          if (controller.error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: controller.error!),
          ],
          if (controller.sync?.failures.isNotEmpty ?? false) ...[
            const SizedBox(height: 12),
            _PartialFailureBanner(
              failureCount: controller.sync!.failures.length,
              onOpenDiagnostics: onOpenDiagnostics,
            ),
          ],
          const SizedBox(height: 14),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.checklist),
                label: Text('待办'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.calendar_month),
                label: Text('日历'),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.school),
                label: Text('课程表'),
              ),
            ],
            selected: {tabIndex},
            onSelectionChanged: (values) => onTabChanged(values.first),
          ),
          const SizedBox(height: 14),
          if (tabIndex == 0)
            _TodoView(controller: controller, onItemTap: onItemTap)
          else if (tabIndex == 1)
            MonthCalendar(items: controller.items, onItemTap: onItemTap)
          else
            const _CoursePlaceholder(),
        ],
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final lastSyncedAt = controller.sync?.lastSyncedAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '作业考试',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (controller.refreshing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            if (controller.refreshing) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value:
                    controller.syncProgress != null &&
                        controller.syncProgress!.total > 0
                    ? controller.syncProgress!.completed /
                          controller.syncProgress!.total
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                controller.syncProgress?.description ?? '准备同步',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Metric(label: '全部', value: '${controller.items.length}'),
                _Metric(label: '今日', value: '${controller.todayItems.length}'),
                _Metric(
                  label: '即将截止',
                  value: '${controller.dueSoonItems.length}',
                ),
                _Metric(
                  label: '已过期',
                  value: '${controller.overdueItems.length}',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              lastSyncedAt == null
                  ? '尚未同步'
                  : '上次同步 ${DateFormat('M月d日 HH:mm').format(lastSyncedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _TodoView extends StatelessWidget {
  const _TodoView({required this.controller, required this.onItemTap});

  final AppController controller;
  final ValueChanged<SyncItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    if (controller.items.isEmpty) {
      return const _BlankState(
        icon: Icons.inbox,
        title: '暂时没有待办',
        body: '同步成功后，作业和考试会显示在这里；未识别到截止时间的项目也会保留。',
      );
    }

    return Column(
      children: [
        _Section(
          title: '已过期',
          items: controller.overdueItems,
          onItemTap: onItemTap,
        ),
        _Section(
          title: '今日截止',
          items: controller.todayItems,
          onItemTap: onItemTap,
        ),
        _Section(
          title: '未来待办',
          items: controller.upcomingItems,
          onItemTap: onItemTap,
        ),
        _Section(
          title: '未识别截止时间',
          items: controller.unscheduledItems,
          onItemTap: onItemTap,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.onItemTap,
  });

  final String title;
  final List<SyncItem> items;
  final ValueChanged<SyncItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SyncItemCard(item: item, onTap: () => onItemTap(item)),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
        title: const Text('同步遇到问题'),
        subtitle: Text(message),
      ),
    );
  }
}

class _PartialFailureBanner extends StatelessWidget {
  const _PartialFailureBanner({
    required this.failureCount,
    required this.onOpenDiagnostics,
  });

  final int failureCount;
  final VoidCallback onOpenDiagnostics;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: ListTile(
        leading: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
        title: Text('部分数据源同步失败（$failureCount）'),
        subtitle: const Text('已有结果仍会保留；可打开诊断查看脱敏后的失败阶段。'),
        trailing: TextButton(
          onPressed: onOpenDiagnostics,
          child: const Text('查看诊断'),
        ),
      ),
    );
  }
}

class _EmptySetup extends StatelessWidget {
  const _EmptySetup({required this.onOpenSettings, this.onOpenLogin});

  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cookie, size: 44),
                  const SizedBox(height: 12),
                  Text(
                    '配置学习通 Cookie',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    onOpenLogin == null
                        ? '填入当前浏览器登录态 Cookie 后，本地抓取即将到来的作业和考试。'
                        : '在 App 内登录学习通后，将自动导入登录态并开始本地同步。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      if (onOpenLogin != null)
                        FilledButton.icon(
                          onPressed: onOpenLogin,
                          icon: const Icon(Icons.login),
                          label: const Text('登录学习通'),
                        ),
                      OutlinedButton.icon(
                        onPressed: onOpenSettings,
                        icon: const Icon(Icons.cookie_outlined),
                        label: const Text('手动导入 Cookie'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoursePlaceholder extends StatelessWidget {
  const _CoursePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const _BlankState(
      icon: Icons.school,
      title: '课程表稍后接入',
      body: '第一版先展示作业考试日历。真实课程表会在后续接入抓取或手动录入。',
    );
  }
}

class _BlankState extends StatelessWidget {
  const _BlankState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
