import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A holographic Fayda / National ID card preview.
/// Keeps the dark card design for contrast against the light-mode UI.
class DigitalIdCardPreview extends StatefulWidget {
  final String faydaNumber;
  final String fullName;
  final String? dateOfBirth;
  final String? gender;
  final bool isVerified;

  const DigitalIdCardPreview({
    super.key,
    required this.faydaNumber,
    this.fullName = '',
    this.dateOfBirth,
    this.gender,
    this.isVerified = false,
  });

  @override
  State<DigitalIdCardPreview> createState() => _DigitalIdCardPreviewState();
}

class _DigitalIdCardPreviewState extends State<DigitalIdCardPreview> with SingleTickerProviderStateMixin {
  late AnimationController _sheenController;
  late Animation<double> _sheenAnimation;

  @override
  void initState() {
    super.initState();
    _sheenController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    _sheenAnimation = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _sheenController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _sheenController.dispose();
    super.dispose();
  }

  String _formatPartitionedNumber(String raw) {
    final clean = raw.replaceAll(RegExp(r'\s+'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      if (i > 0 && i % 4 == 0) buffer.write('  ');
      if (i < clean.length) {
        buffer.write(clean[i]);
      } else {
        buffer.write('•');
      }
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final cleanDigits = widget.faydaNumber.replaceAll(RegExp(r'\D'), '');
    final isComplete = cleanDigits.length == 16;
    final displayName = widget.fullName.trim().isEmpty ? 'ETHIOPIAN RESIDENT' : widget.fullName.trim().toUpperCase();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1E1B4B), // Deep Indigo
            Color(0xFF312E81), // Indigo 800
            Color(0xFF1E1B4B),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isComplete ? AppColors.primary.withAlpha(200) : Colors.white.withAlpha(30),
          width: isComplete ? 2.0 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isComplete ? AppColors.primary.withAlpha(40) : AppColors.shadowHeavy,
            blurRadius: isComplete ? 24 : 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Background Watermark Shield
          const Positioned(
            right: -20,
            bottom: -20,
            child: Opacity(
              opacity: 0.05,
              child: Icon(Icons.shield_rounded, size: 220, color: Colors.white),
            ),
          ),

          // Dynamic Holographic Sheen
          AnimatedBuilder(
            animation: _sheenAnimation,
            builder: (context, child) {
              return Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment(_sheenAnimation.value, 0),
                  widthFactor: 0.5,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.white.withAlpha(15),
                          AppColors.primary.withAlpha(25),
                          Colors.white.withAlpha(15),
                          Colors.transparent,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(40),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.primary.withAlpha(80)),
                            ),
                            child: const Icon(Icons.fingerprint_rounded, color: AppColors.primaryMuted, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'FAYDA NATIONAL ID',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                    letterSpacing: 0.8,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'FDRE NATIONAL ID PROGRAM',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(140),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 9.5,
                                    letterSpacing: 0.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Status Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isComplete ? AppColors.primary.withAlpha(30) : Colors.white.withAlpha(15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isComplete ? AppColors.primaryMuted : Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isComplete ? AppColors.primary : AppColors.warning,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isComplete ? '16 DIGITS' : '${cleanDigits.length}/16',
                            style: TextStyle(
                              color: isComplete ? AppColors.primaryMuted : Colors.white70,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Chip & contactless
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 28,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFCD34D), Color(0xFFD97706)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFB45309), width: 1),
                      ),
                      child: Stack(
                        children: [
                          Center(child: Container(width: 24, height: 1, color: const Color(0xFF78350F).withAlpha(150))),
                          Center(child: Container(width: 1, height: 16, color: const Color(0xFF78350F).withAlpha(150))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.contactless_rounded, color: Colors.white54, size: 20),
                  ],
                ),

                const SizedBox(height: 16),

                // Number & Name
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _formatPartitionedNumber(widget.faydaNumber),
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.2,
                          shadows: isComplete
                              ? [Shadow(color: AppColors.primary.withAlpha(200), blurRadius: 10)]
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: TextStyle(
                              color: Colors.white.withAlpha(220),
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 0.6,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.gender != null || widget.dateOfBirth != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            [if (widget.gender != null) widget.gender, if (widget.dateOfBirth != null) widget.dateOfBirth].join(' • '),
                            style: TextStyle(color: Colors.white.withAlpha(150), fontWeight: FontWeight.w500, fontSize: 10.5),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
