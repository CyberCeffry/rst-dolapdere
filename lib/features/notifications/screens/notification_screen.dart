import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_helper.dart';
import '../../../models/contract_model.dart';
import '../../../models/customer_model.dart';

Uri buildCustomerReminderEmailUri({
  required String email,
  required String subject,
  required String body,
}) => Uri.parse(
  'mailto:$email?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
);

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({
    super.key,
    required this.store,
    this.onReviewContract,
  });

  final AppStore store;
  final ValueChanged<String>? onReviewContract;

  Future<void> _openCustomerEmail(
    BuildContext context,
    ContractModel contract,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final customer = store.customerFor(contract.customerId);
    final email = customer?.email.trim() ?? '';
    if (email.isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('Müşterinin e-posta adresi kayıtlı değil.'),
        ),
      );
      return;
    }
    final space = store.adSpaceFor(contract.adSpaceId);
    final subject =
        'Sözleşme bitiş hatırlatması - ${space?.name ?? 'Reklam alanı'}';
    final body = [
      'Merhaba ${customer?.name ?? ''},',
      '',
      '${space?.name ?? 'Reklam alanı'} için sözleşmeniz ${DateFormat('dd.MM.yyyy').format(contract.endDate)} tarihinde sona eriyor.',
      '',
      'RST Dolapdere',
    ].join('\n');
    final uri = buildCustomerReminderEmailUri(
      email: email,
      subject: subject,
      body: body,
    );
    if (!await launchUrl(uri)) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('E-posta uygulaması açılamadı.')),
      );
    }
  }

  Future<void> _openWhatsApp(
    BuildContext context,
    ContractModel contract,
  ) async {
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
    final text =
        'RST Dolapdere sözleşme hatırlatması: '
        '${customer?.name ?? 'Kiracı'} kiracısının ${space?.name ?? 'Reklam alanı'} '
        'sözleşmesi ${DateFormat('dd.MM.yyyy').format(contract.endDate)} tarihinde sona eriyor.';
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
                  (contract) => DateHelper.daysUntil(contract.endDate) <= 10,
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
                '10, 5 ve son gün hatırlatmaları',
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
                    showEmail: store.emailRemindersEnabled,
                    showWhatsapp: store.whatsappRemindersEnabled,
                    onEmail: () => _openCustomerEmail(context, contract),
                    onWhatsapp: () => _openWhatsApp(context, contract),
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
    required this.showEmail,
    required this.showWhatsapp,
    required this.onEmail,
    required this.onWhatsapp,
    required this.onReview,
  });

  final ContractModel contract;
  final CustomerModel? customer;
  final String spaceName;
  final bool showEmail;
  final bool showWhatsapp;
  final VoidCallback onEmail;
  final VoidCallback onWhatsapp;
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
                  days == 0 ? 'Bugün' : '$days gün',
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
                for (final threshold in [10, 5, 0])
                  _ReminderChip(
                    label: threshold == 0 ? 'Son gün' : '$threshold gün kala',
                    active: days <= threshold,
                  ),
              ],
            ),
            if (showEmail ||
                showWhatsapp ||
                (customer?.email ?? '').trim().isNotEmpty ||
                (customer?.phone ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (showEmail)
                    const Chip(
                      avatar: Icon(
                        Icons.mark_email_read_outlined,
                        size: 16,
                        color: AppColors.success,
                      ),
                      label: Text('Otomatik e-posta açık'),
                    ),
                  if (showWhatsapp)
                    const Chip(
                      avatar: Icon(
                        Icons.mark_chat_read_outlined,
                        size: 16,
                        color: AppColors.success,
                      ),
                      label: Text('Otomatik WhatsApp açık'),
                    ),
                  if ((customer?.email ?? '').trim().isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: onEmail,
                      icon: const Icon(Icons.email_outlined),
                      label: const Text('Müşteriye e-posta'),
                    ),
                  if ((customer?.phone ?? '').trim().isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: onWhatsapp,
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('WhatsApp'),
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
