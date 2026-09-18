import 'package:flutter/material.dart';

import '../../controllers/flow_controller.dart';
import '../../theme/app_colors.dart';
import '../../widgets/revolut_receipt_sheet.dart';

class ActivityTab extends StatefulWidget {
  final Map<String, FlowController> activeDrafts;
  final Function(FlowController) onResumeFlow;
  final Function(FlowController) onDiscardDraft;

  const ActivityTab({
    super.key,
    required this.activeDrafts,
    required this.onResumeFlow,
    required this.onDiscardDraft,
  });

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  String _filter = 'All';

  final List<Map<String, dynamic>> _mockCompletedRecords = [
    {
      'id': '#KIF-8821',
      'name': 'Dawit Alemu',
      'type': 'Individual KYC',
      'category': 'KYC',
      'time': '12 mins ago',
      'date': 'Today',
      'status': 'Synced',
      'data': {
        'kyc.fullName': 'Dawit Alemu',
        'kyc.phoneNumber': '+251911223344',
        'kyc.faydaNumber': '1042893175820491',
        'kyc.gender': 'Male',
        'kyc.city': 'Addis Ababa',
      },
    },
    {
      'id': '#KIF-8820',
      'name': 'Selam Grocery PLC',
      'type': 'Merchant KYB',
      'category': 'KYB',
      'time': '45 mins ago',
      'date': 'Today',
      'status': 'Synced',
      'data': {
        'kyb.businessName': 'Selam Grocery PLC',
        'kyb.tinNumber': '0098472910',
        'kyb.tradeLicense': 'TL-AA-8820',
        'kyb.ownerPhone': '+251922334455',
        'kyb.location': 'Bole Subcity',
      },
    },
    {
      'id': '#KIF-8819',
      'name': 'Marta Tadesse',
      'type': 'Fayda Fast Track',
      'category': 'Identity',
      'time': '2 hours ago',
      'date': 'Today',
      'status': 'Verified',
      'data': {
        'fayda.fullName': 'Marta Tadesse',
        'fayda.faydaId': '8839201948271039',
        'fayda.verificationResult': 'Biometrics Matched 99.4%',
      },
    },
    {
      'id': '#KIF-8818',
      'name': 'Habtamu Desta',
      'type': 'Agri-Credit Loan',
      'category': 'Lending',
      'time': 'Yesterday',
      'date': 'Yesterday',
      'status': 'Synced',
      'data': {
        'agri.farmerName': 'Habtamu Desta',
        'agri.coopId': 'Oromia Coffee Union #44',
        'agri.loanAmount': 'ETB 150,000',
        'agri.landSize': '4.5 Hectares',
      },
    },
  ];

  void _inspectReceipt(Map<String, dynamic> record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return RevolutReceiptSheet(
              flowTitle: record['type'] as String,
              category: record['category'] as String,
              collectedData: record['data'] as Map<String, dynamic>,
              onConfirmAndSync: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Receipt ${record['id']} exported.')),
                );
              },
              onEditStage: () => Navigator.pop(context),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final drafts = widget.activeDrafts.values.toList();
    final hasDrafts = drafts.isNotEmpty;

    final filteredRecords = _mockCompletedRecords.where((r) {
      if (_filter == 'All') return true;
      return r['status'] == _filter;
    }).toList();

    // Group by date
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final rec in filteredRecords) {
      final date = rec['date'] as String;
      grouped.putIfAbsent(date, () => []).add(rec);
    }

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          // Header
          const Text(
            'Activity',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Your field registration history',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // Drafts Section
          if (hasDrafts) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.pending_actions_rounded, size: 16, color: AppColors.warningDark),
                    SizedBox(width: 6),
                    Text('Pending Drafts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${drafts.length}',
                    style: const TextStyle(color: AppColors.warningDark, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...drafts.map((d) => _buildDraftCard(d)),
            const SizedBox(height: 20),
          ],

          // Filter Chips
          Row(
            children: ['All', 'Synced', 'Verified'].map((tab) {
              final isSel = _filter == tab;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(tab),
                  selected: isSel,
                  onSelected: (_) => setState(() => _filter = tab),
                  selectedColor: AppColors.primaryLight,
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: isSel ? AppColors.primary : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: isSel ? AppColors.primary.withAlpha(80) : AppColors.border),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Date-grouped records
          ...grouped.entries.expand((group) => [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(
                group.key,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.3),
              ),
            ),
            Container(
              decoration: AppColors.cardDecoration,
              child: Column(
                children: group.value.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final rec = entry.value;
                  final isLast = idx == group.value.length - 1;
                  return _buildRecordRow(rec, isLast);
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
          ]),
        ],
      ),
    );
  }

  Widget _buildRecordRow(Map<String, dynamic> rec, bool isLast) {
    final statusColor = rec['status'] == 'Verified' ? AppColors.primary : AppColors.success;
    final statusBg = rec['status'] == 'Verified' ? AppColors.primaryLight : AppColors.successLight;

    return InkWell(
      onTap: () => _inspectReceipt(rec),
      borderRadius: BorderRadius.vertical(
        top: Radius.zero,
        bottom: isLast ? const Radius.circular(16) : Radius.zero,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceDim,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.receipt_long_rounded, color: AppColors.textSecondary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    rec['name'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${rec['type']} • ${rec['time']}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    rec['status'] as String,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 10.5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(rec['id'] as String, style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftCard(FlowController draft) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withAlpha(50)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warning.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.edit_note_rounded, color: AppColors.warningDark, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  draft.manifest.title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary),
                ),
                Text('Paused at ${draft.progressLabel}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => widget.onDiscardDraft(draft),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warningDark,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () => widget.onResumeFlow(draft),
            child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
