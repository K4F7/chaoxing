import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/sync_item.dart';
import '../services/chaoxing_url_policy.dart';
import '../widgets/status_pill.dart';

class DetailScreen extends StatelessWidget {
  const DetailScreen({required this.item, super.key});

  final SyncItem item;

  @override
  Widget build(BuildContext context) {
    final kindLabel = item.isExam ? '考试' : '作业';
    final trustedUrl = isTrustedChaoxingUrl(item.url);
    return Scaffold(
      appBar: AppBar(title: Text(kindLabel)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        item.isExam
                            ? Icons.assignment_turned_in
                            : Icons.edit_note,
                      ),
                      const SizedBox(width: 8),
                      Text(kindLabel),
                      const SizedBox(width: 8),
                      StatusPill(item: item),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _InfoCard(
            rows: [
              _InfoRow('开始时间', _formatDate(item.startAt)),
              _InfoRow('截止时间', _formatDate(item.dueAt)),
              _InfoRow('学习通状态', item.status),
              _InfoRow('来源通知', item.sourceTitle),
              _InfoRow('通知时间', item.sourceSendTime ?? '无'),
              _InfoRow('课程 ID', item.courseId ?? '无'),
              _InfoRow('班级 ID', item.classId ?? '无'),
              _InfoRow('作业/考试 ID', item.workId ?? item.answerId ?? '无'),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: trustedUrl ? () => _openTrustedUrl(context) : null,
            icon: const Icon(Icons.open_in_new),
            label: Text(trustedUrl ? '打开学习通链接' : '学习通链接不可用'),
          ),
        ],
      ),
    );
  }

  Future<void> _openTrustedUrl(BuildContext context) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(item.url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开学习通链接')));
    }
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: rows
              .map(
                (row) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text(
                          row.label,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row.value.isEmpty ? '无' : row.value,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _InfoRow {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return '无';
  }
  return DateFormat('yyyy年M月d日 HH:mm').format(value);
}
