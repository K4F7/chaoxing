import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sync_item.dart';
import '../state/app_controller.dart';
import '../widgets/month_calendar.dart';
import '../widgets/sync_item_card.dart';
import 'detail_screen.dart';
import 'settings_screen.dart';

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
            )
          : _EmptySetup(onOpenSettings: () => _openSettings(context)),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          initialConfig: widget.controller.config,
          onSave: widget.controller.saveConfig,
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, SyncItem item) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => DetailScreen(item: item)));
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.controller,
    required this.tabIndex,
    required this.onTabChanged,
    required this.onItemTap,
  });

  final AppController controller;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  final ValueChanged<SyncItem> onItemTap;

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
        body: '同步成功后，解析到截止时间的作业和考试会显示在这里。',
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

class _EmptySetup extends StatelessWidget {
  const _EmptySetup({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

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
                  const Icon(Icons.cloud_sync, size: 44),
                  const SizedBox(height: 12),
                  Text(
                    '连接你的 Worker',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '填写 Worker URL 和 RUN_TOKEN 后即可同步学习通作业考试。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('打开设置'),
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
