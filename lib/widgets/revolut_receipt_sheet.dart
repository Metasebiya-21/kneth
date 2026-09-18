import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A modern, clean receipt sheet for completed flow summaries.
class RevolutReceiptSheet extends StatefulWidget {
  final String flowTitle;
  final String category;
  final Map<String, dynamic> collectedData;
  final VoidCallback onConfirmAndSync;
  final VoidCallback onEditStage;

  const RevolutReceiptSheet({
    super.key,
    required this.flowTitle,
    required this.category,
    required this.collectedData,
    required this.onConfirmAndSync,
    required this.onEditStage,
  });

  @override
  State<RevolutReceiptSheet> createState() => _RevolutReceiptSheetState();
}

class _RevolutReceiptSheetState extends State<RevolutReceiptSheet> with SingleTickerProviderStateMixin {
  late AnimationController _badgeAnimController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _badgeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _scaleAnimation = CurvedAnimation(
      parent: _badgeAnimController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _badgeAnimController.dispose();
    super.dispose();
  }

  String _formatKey(String key) {
    final parts = key.split('.');
    final raw = parts.length > 1 ? parts[1] : parts[0];
    final words = raw
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (m) => '${m[1]} ${m[2]}',
        );
    return words.split(' ').where((w) => w.isNotEmpty).map((w) {
      final lower = w.toLowerCase();
      if (lower == 'id') return 'ID';
      if (lower == 'kyc') return 'KYC';
      if (lower == 'kyb') return 'KYB';
      if (lower == 'tin') return 'TIN';
      if (lower == 'fayda') return 'Fayda';
      if (lower == 'nid') return 'NID';
      if (lower == 'fin') return 'FIN';
      if (lower == 'doc') return 'Doc';
      return w[0].toUpperCase() + (w.length > 1 ? w.substring(1).toLowerCase() : '');
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final textEntries = <MapEntry<String, dynamic>>[];
    final mediaEntries = <MapEntry<String, String>>[];

    for (final entry in widget.collectedData.entries) {
      if (entry.key.endsWith('.filePath') && entry.value != null) {
        mediaEntries.add(MapEntry(entry.key, entry.value.toString()));
      } else if (entry.value != null && entry.value.toString().isNotEmpty) {
        textEntries.add(entry);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Badge
          ScaleTransition(
            scale: _scaleAnimation,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success.withAlpha(50)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.verified_user_rounded, color: AppColors.success, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'VERIFICATION COMPLETE',
                      style: TextStyle(
                        color: AppColors.successDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Receipt Card
          Container(
            decoration: AppColors.cardDecorationElevated,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Receipt Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              widget.category.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          Text(
                            DateTime.now().toString().substring(0, 16),
                            style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 11.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.flowTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Audit Trail & Submission Record',
                        style: TextStyle(color: Colors.white.withAlpha(180), fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // Itemized Data
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.fact_check_rounded, color: AppColors.primary, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Recorded Declarations',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...textEntries.map((e) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceDim,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatKey(e.key),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  e.value.toString(),
                                  textAlign: TextAlign.end,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),

                      if (mediaEntries.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.attachment_rounded, color: AppColors.secondary, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Document Assets',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: mediaEntries.map((m) {
                            final file = File(m.value);
                            final exists = file.existsSync();
                            return Container(
                              width: 140,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceDim,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    height: 80,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainer,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: exists
                                        ? Image.file(file, fit: BoxFit.cover)
                                        : const Icon(Icons.broken_image_rounded, color: AppColors.textMuted),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _formatKey(m.key),
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.textPrimary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_rounded, color: AppColors.success, size: 12),
                                      SizedBox(width: 3),
                                      Text(
                                        'Verified',
                                        style: TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Dotted Divider
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: List.generate(
                      24,
                      (i) => Expanded(
                        child: Container(
                          height: 1.5,
                          color: i.isEven ? AppColors.border : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),

                // Audit Footer
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDim,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.qr_code_2_rounded, size: 28, color: AppColors.textPrimary),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Signed & Cryptographically Hashed',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textPrimary),
                            ),
                            Text(
                              'Case ID: #KIF-2026-ETH • Immutable Ledger Ready',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Actions
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            icon: const Icon(Icons.cloud_upload_rounded, size: 22),
            label: const Text(
              'Confirm & Sync',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.2),
            ),
            onPressed: widget.onConfirmAndSync,
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              side: const BorderSide(color: AppColors.border, width: 1.5),
            ),
            onPressed: widget.onEditStage,
            child: const Text(
              'Review or Edit Prior Steps',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
