import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../providers/notification_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().loadNotifications();
    });
  }

  IconData _getIcon(String type) {
    switch (type) {
      case 'hearing_reminder':
        return Icons.event_rounded;
      case 'payment_reminder':
        return Icons.payment_rounded;
      case 'case_update':
        return Icons.gavel_rounded;
      case 'document_upload':
        return Icons.upload_file_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getColor(String type) {
    switch (type) {
      case 'hearing_reminder':
        return AppColors.info;
      case 'payment_reminder':
        return AppColors.warning;
      case 'case_update':
        return AppColors.gold;
      case 'document_upload':
        return AppColors.success;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.primaryDark,
        title: const Text('Notifications',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (provider.notifications.isNotEmpty)
            TextButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                for (final n in provider.notifications) {
                  if (!(n['is_read'] ?? false)) {
                    provider.markAsRead(n['id']);
                  }
                }
              },
              child: const Text('Mark all read',
                  style: TextStyle(color: AppColors.gold, fontSize: 12)),
            ),
        ],
      ),
      body: provider.loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.gold))
          : provider.notifications.isEmpty
              ? _EmptyState()
              : RefreshIndicator(
                  color: AppColors.gold,
                  onRefresh: () => provider.loadNotifications(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: provider.notifications.length,
                    itemBuilder: (_, i) {
                      final n = provider.notifications[i];
                      final isRead = n['is_read'] ?? false;
                      final type = n['type'] ?? 'general';
                      final color = _getColor(type);
                      final icon = _getIcon(type);

                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          provider.markAsRead(n['id']);
                          _openReference(context, n);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isRead
                                ? AppColors.bgCard
                                : color.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isRead
                                  ? AppColors.border
                                  : color.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(icon, color: color, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            n['title'] ?? '',
                                            style: TextStyle(
                                              color: AppColors.textPrimary,
                                              fontWeight: isRead
                                                  ? FontWeight.w500
                                                  : FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        if (!isRead)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    if ((n['message'] ?? '').isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        n['message'],
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                          height: 1.4,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Text(
                                      _formatTime(n['created_at'] ?? ''),
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  // Every notification already carries the reference_id/reference_type the
  // backend wrote via utils.NotifyWithRef — this just routes to the existing
  // screen for that reference instead of leaving the tap as a no-op read.
  void _openReference(BuildContext context, dynamic n) {
    final refId = (n['reference_id'] ?? '').toString();
    final refType = (n['reference_type'] ?? '').toString();
    if (refId.isEmpty) return;
    switch (refType) {
      case 'case':
        context.push('/cases/$refId');
        break;
      case 'chat_room':
        context.push('/chat/$refId');
        break;
      case 'consultation':
        context.push('/lawyer/consultations');
        break;
      case 'invoice':
      case 'payment':
        context.push('/billing');
        break;
    }
  }

  String _formatTime(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_none_rounded,
                color: AppColors.textMuted, size: 40),
          ),
          const SizedBox(height: 16),
          const Text('No notifications yet',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('You are all caught up!',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }
}
