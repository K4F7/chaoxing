import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_sync_response.dart';
import '../utils/redaction.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    required this.sync,
    required this.error,
    required this.onCopyDiagnostics,
    super.key,
  });

  final AppSyncResponse? sync;
  final String? error;
  final Future<void> Function() onCopyDiagnostics;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  bool _copying = false;

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;
    return Scaffold(
      appBar: AppBar(title: const Text('同步诊断')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _copying ? null : _copyDiagnostics,
          icon: const Icon(Icons.copy_all_outlined),
          label: Text(_copying ? '复制中' : '复制脱敏诊断'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _DiagnosticsSummary(sync: sync, error: widget.error),
          const SizedBox(height: 14),
          Text(
            '最近失败',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (sync == null || sync.failures.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('没有记录到解析失败'),
              ),
            )
          else
            ...sync.failures
                .take(10)
                .map(
                  (failure) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(Icons.warning_amber_outlined),
                        title: Text(redactSensitiveText(failure.sourceTitle)),
                        subtitle: Text(redactSensitiveText(failure.message)),
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 8),
          const Text(
            '诊断内容不包含 Cookie、通知正文或完整敏感 query；复制后请仍在发送前检查内容。',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _copyDiagnostics() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _copying = true);
    try {
      await widget.onCopyDiagnostics();
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('脱敏诊断信息已复制')));
      }
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('复制诊断失败，请稍后重试')));
      }
    } finally {
      if (mounted) {
        setState(() => _copying = false);
      }
    }
  }
}

class _DiagnosticsSummary extends StatelessWidget {
  const _DiagnosticsSummary({required this.sync, required this.error});

  final AppSyncResponse? sync;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final lastSyncedAt = sync?.lastSyncedAt;
    final stats = sync?.stats ?? const SyncStats();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '运行状态',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _SummaryRow(label: '认证状态', value: sync?.authStatus ?? 'unknown'),
            _SummaryRow(
              label: '最近同步',
              value: lastSyncedAt == null
                  ? '尚未同步'
                  : DateFormat('yyyy-MM-dd HH:mm').format(lastSyncedAt),
            ),
            _SummaryRow(
              label: '同步耗时',
              value: _formatDuration(stats.durationMs),
            ),
            if (stats.durationMs > 0) ...[
              _SummaryRow(
                label: '认证耗时',
                value: _formatDuration(stats.authenticationMs),
              ),
              _SummaryRow(label: '通知耗时', value: _formatDuration(stats.inboxMs)),
              _SummaryRow(
                label: '通知详情耗时',
                value: _formatDuration(stats.noticeDetailsMs),
              ),
              _SummaryRow(
                label: '任务详情耗时',
                value: _formatDuration(stats.assignmentDetailsMs),
              ),
              if (stats.courseSourcesEnabled)
                _SummaryRow(
                  label: '课程耗时',
                  value: _formatDuration(stats.coursesMs),
                ),
            ],
            _SummaryRow(label: '待办数量', value: '${sync?.items.length ?? 0}'),
            _SummaryRow(label: '收件箱消息', value: '${stats.inboxMessages}'),
            _SummaryRow(label: '相关通知', value: '${stats.relevantNotices}'),
            _SummaryRow(label: '通知详情', value: '${stats.detailSummaries}'),
            _SummaryRow(label: '收件箱任务链接', value: '${stats.inboxTaskLinks}'),
            _SummaryRow(label: '收件箱详情请求', value: '${stats.inboxTaskDetails}'),
            _SummaryRow(
              label: '收件箱状态过滤',
              value: '${stats.statusFilteredItems}',
            ),
            if (stats.courseSourcesEnabled) ...[
              _SummaryRow(label: '课程数量', value: '${stats.courses}'),
              _SummaryRow(
                label: '课程发现链接',
                value: '${stats.courseTaskLinksDiscovered}',
              ),
              _SummaryRow(label: '课程详情请求', value: '${stats.courseTaskLinks}'),
              _SummaryRow(
                label: '课程状态过滤',
                value: '${stats.courseTaskStatusFiltered}',
              ),
            ],
            _SummaryRow(label: '可行动去重项', value: '${stats.itemCandidates}'),
            _SummaryRow(label: '失败数量', value: '${sync?.failures.length ?? 0}'),
            if (sync?.items.isEmpty == true)
              _SummaryRow(label: '空结果判断', value: _emptyResultHint(sync!)),
            _SummaryRow(
              label: '最近错误',
              value: error == null ? '无' : redactSensitiveText(error!),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(int milliseconds) {
  if (milliseconds <= 0) {
    return '未记录';
  }
  if (milliseconds < 1000) {
    return '$milliseconds 毫秒';
  }
  final seconds = milliseconds / 1000;
  if (seconds < 60) {
    return '${seconds.toStringAsFixed(1)} 秒';
  }
  final duration = Duration(milliseconds: milliseconds);
  return '${duration.inMinutes} 分 ${duration.inSeconds.remainder(60)} 秒';
}

String _emptyResultHint(AppSyncResponse sync) {
  final stats = sync.stats;
  if (sync.authStatus != 'ok') {
    return '登录状态异常，请重新登录';
  }
  if (sync.failures.isNotEmpty) {
    return '同步过程中存在失败，请查看下方记录';
  }
  if (stats.statusFilteredItems + stats.courseTaskStatusFiltered > 0 &&
      stats.itemCandidates == 0) {
    return '发现的事项均已完成、已提交或已结束';
  }
  if (stats.inboxMessages == 0 && stats.courses == 0) {
    return stats.courseSourcesEnabled
        ? '收件箱和课程空间都没有返回可扫描内容'
        : '收件箱没有返回消息，课程补充同步未开启';
  }
  if (stats.inboxMessages > 0 &&
      stats.relevantNotices == 0 &&
      stats.courseTaskLinksDiscovered == 0) {
    return '收件箱有消息，但没有识别到作业或考试通知';
  }
  if (stats.detailSummaries > 0 &&
      stats.inboxTaskLinks == 0 &&
      stats.courseTaskLinksDiscovered == 0) {
    return '通知详情已读取，但没有识别到任务入口';
  }
  return '已完成扫描，但没有生成待办；可复制诊断继续排查';
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
