import 'package:flutter/material.dart';

import '../../controllers/flow_controller.dart';
import '../../widgets/revolut_receipt_sheet.dart';

class CaseHistoryTab extends StatefulWidget {
  final Map<String, FlowController> activeDrafts;
  final Function(FlowController) onResumeFlow;
  final Function(FlowController) onDiscardDraft;

  const CaseHistoryTab({
    super.key,
    required this.activeDrafts,
    required this.onResumeFlow,
    required this.onDiscardDraft,
  });

  @override
  State<CaseHistoryTab> createState() => _CaseHistoryTabState();
}

class _CaseHistoryTabState extends State<CaseHistoryTab> {
  String _filter = 'All';

  final List<Map<String, dynamic>> _mockCompletedRecords = [
    {
      'id': '#KIF-8821',
      'name': 'Dawit Alemu',
      'type': 'Individual KYC',
      'category': 'KYC',
      'time': '12 mins ago',
      'date': 'Sep 18, 2026',
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
      'date': 'Sep 18, 2026',
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
      'date': 'Sep 18, 2026',
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
      'date': 'Sep 17, 2026',
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
      backgroundColor: const Color(0xFF0F172A),
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
                  SnackBar(
                    content: Text('Receipt #${record['id']} verified & exported.'),
                  ),
                );
              },
              onEditStage: () {
                Navigator.pop(context);
              },
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
      if (_filter == 'Synced') return r['status'] == 'Synced';
      if (_filter == 'Verified') return r['status'] == 'Verified';
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        // Header
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Case Registry',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE2E8F0),
                letterSpacing: -0.5,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Complete field registration audit trail',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Drafts Section (if any active)
        if (hasDrafts) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_rounded, size: 18, color: Color(0xFFFBBF24)),
                  SizedBox(width: 6),
                  Text('Paused Offline Drafts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFFE2E8F0))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7).withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${drafts.length} Saved', style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...drafts.map((d) => _buildDraftCard(d)),
          const SizedBox(height: 20),
        ],

        // Filter Tabs
        Row(
          children: ['All', 'Synced', 'Verified'].map((tab) {
            final isSel = _filter == tab;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(tab),
                selected: isSel,
                onSelected: (_) => setState(() => _filter = tab),
                selectedColor: const Color(0xFF34D399),
                labelStyle: TextStyle(
                  color: isSel ? const Color(0xFF06281B) : const Color(0xFFCBD5E1),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                backgroundColor: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: isSel ? const Color(0xFF34D399) : const Color(0xFF334155)),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),

        // Completed Records List
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF334155)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: filteredRecords.asMap().entries.map((entry) {
              final idx = entry.key;
              final rec = entry.value;
              final isLast = idx == filteredRecords.length - 1;

              return InkWell(
                onTap: () => _inspectReceipt(rec),
                borderRadius: BorderRadius.vertical(
                  top: idx == 0 ? const Radius.circular(22) : Radius.zero,
                  bottom: isLast ? const Radius.circular(22) : Radius.zero,
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFF334155))),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF064E3B),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF34D399), size: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              rec['name'] as String,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFFE2E8F0)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${rec['type']} • ${rec['time']}',
                              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
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
                              color: const Color(0xFF064E3B),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              rec['status'] as String,
                              style: const TextStyle(color: Color(0xFF6EE7B7), fontWeight: FontWeight.w800, fontSize: 10.5),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(rec['id'] as String, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildDraftCard(FlowController draft) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFB45309).withAlpha(140)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7).withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.edit_note_rounded, color: Color(0xFFFBBF24), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  draft.manifest.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFE2E8F0)),
                ),
                const SizedBox(height: 2),
                Text('Paused at ${draft.progressLabel}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF94A3B8), size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: () => widget.onDiscardDraft(draft),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF34D399),
              foregroundColor: const Color(0xFF06281B),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => widget.onResumeFlow(draft),
            child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
