import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../../models/app_user.dart';
import '../../../models/contract_model.dart';
import '../../../models/customer_model.dart';

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({
    super.key,
    required this.store,
    this.user,
    this.onReviewContract,
  });

  final AppStore store;
  final AppUser? user;
  final ValueChanged<String>? onReviewContract;

  Future<void> _openWhatsApp(
    BuildContext context,
    ContractModel contract,
  ) async {
    if (user?.role != AppRole.admin) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final customer = store.customerFor(contract.customerId);
    var phone = (customer?.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Müşterinin telefon numarası kayıtlı değil.'),
        ),
      );
      return;
    }
    if (phone.startsWith('00')) phone = phone.substring(2);
    if (phone.startsWith('0')) phone = phone.substring(1);
    if (phone.length == 10) phone = '90$phone';
    final space = store.adSpaceFor(contract.adSpaceId);
    final daysRemaining = DateHelper.daysUntil(contract.endDate);
    final remainingText = switch (daysRemaining) {
      0 => 'Sözleşme bugün sona eriyor.',
      > 0 => 'Sözleşmenin bitmesine $daysRemaining gün kalıyor.',
      _ => 'Sözleşme ${daysRemaining.abs()} gün önce sona erdi.',
    };
    final text =
        'RST Dolapdere sözleşme hatırlatması: '
        '${customer?.name ?? 'Kiracı'} kiracısının ${space?.name ?? 'Reklam alanı'} '
        'sözleşmesi ${DateFormat('dd.MM.yyyy').format(contract.endDate)} tarihinde sona eriyor. '
        '$remainingText';
    final uri = Uri.https('wa.me', '/$phone', {'text': text});
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('WhatsApp açılamadı.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final contracts =
            store.activeContracts
                .where(
                  (contract) =>
                      DateHelper.daysUntil(contract.endDate) <=
                      store.reminderOffsets.reduce((a, b) => a > b ? a : b),
                )
                .toList()
              ..sort((a, b) => a.endDate.compareTo(b.endDate));
        final horizontalPadding = MediaQuery.sizeOf(context).width < 600
            ? 16.0
            : 24.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            20,
            horizontalPadding,
            24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bildirimler',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Seçilen günlerde sözleşme hatırlatmaları',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              if (contracts.isEmpty)
                Card(
                  child: SizedBox(
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 40,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Yaklaşan sözleşme bulunmuyor.',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ...contracts.map(
                  (contract) => _ReminderCard(
                    contract: contract,
                    customer: store.customerFor(contract.customerId),
                    spaceName:
                        store.adSpaceFor(contract.adSpaceId)?.name ??
                        'Reklam alanı',
                    showWhatsapp: user?.role == AppRole.admin,
                    onWhatsapp: () => _openWhatsApp(context, contract),
                    reminderOffsets: store.reminderOffsets,
                    onReview: () => onReviewContract?.call(contract.id),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.contract,
    required this.customer,
    required this.spaceName,
    required this.showWhatsapp,
    required this.onWhatsapp,
    required this.reminderOffsets,
    required this.onReview,
  });

  final ContractModel contract;
  final CustomerModel? customer;
  final String spaceName;
  final bool showWhatsapp;
  final VoidCallback onWhatsapp;
  final List<int> reminderOffsets;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final days = DateHelper.daysUntil(contract.endDate);
    final titleMaxWidth = MediaQuery.sizeOf(context).width < 380
        ? 180.0
        : 220.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.event_busy_outlined,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: titleMaxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spaceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${customer?.name ?? 'Müşteri'} • ${DateFormat('dd.MM.yyyy').format(contract.endDate)}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(
                  days == 0
                      ? 'Bugün'
                      : days > 0
                      ? '$days gün'
                      : '${days.abs()} gün geçti',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.open_in_new),
                label: const Text('İncele'),
              ),
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final threshold in reminderOffsets)
                  _ReminderChip(
                    label: threshold == 0 ? 'Son gün' : '$threshold gün kala',
                    active: days <= threshold,
                  ),
              ],
            ),
            if (showWhatsapp && (customer?.phone ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: onWhatsapp,
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Kiracıya WhatsApp gönder'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReminderChip extends StatelessWidget {
  const _ReminderChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(
      active ? Icons.check_circle : Icons.schedule,
      size: 16,
      color: active
          ? AppColors.success
          : Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    label: Text(label),
    visualDensity: VisualDensity.compact,
  );
}
