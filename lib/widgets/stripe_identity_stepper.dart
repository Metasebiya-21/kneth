import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A Stripe Identity-styled segmented step progress header.
class StripeIdentityStepper extends StatelessWidget implements PreferredSizeWidget {
  final int currentStep;
  final int totalSteps;
  final String stageTitle;
  final String flowTitle;
  final String? estimatedTime;
  final VoidCallback? onBack;

  const StripeIdentityStepper({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.stageTitle,
    required this.flowTitle,
    this.estimatedTime,
    this.onBack,
  });

  @override
  Size get preferredSize => const Size.fromHeight(92);

  @override
  Widget build(BuildContext context) {
    final effectiveTotal = math.max(totalSteps, currentStep);

    return SafeArea(
      bottom: false,
      child: Container(
        height: 92,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1.2),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Navigation Bar Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (onBack != null) ...[
                  IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A), size: 22),
                    onPressed: onBack,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        flowTitle.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF64748B),
                          letterSpacing: 0.8,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stageTitle,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          height: 1.15,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Segmented Counter Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.bolt_rounded, size: 14, color: Color(0xFF059669)),
                      const SizedBox(width: 4),
                      Text(
                        'Step $currentStep of $effectiveTotal',
                        style: const TextStyle(
                          color: Color(0xFF047857),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Stripe Segmented Progress Bars
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(effectiveTotal > 0 ? effectiveTotal : 1, (index) {
                final isCompleted = index < currentStep - 1;
                final isCurrent = index == currentStep - 1;

                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeInOutCubic,
                    height: isCurrent ? 4.5 : 3.5,
                    margin: EdgeInsets.only(
                      left: index == 0 ? 0 : 2.5,
                      right: index == effectiveTotal - 1 ? 0 : 2.5,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: isCompleted
                          ? const Color(0xFF059669) // Green filled
                          : isCurrent
                              ? const Color(0xFF10B981) // Active glowing green
                              : const Color(0xFFE2E8F0), // Inactive slate
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: const Color(0xFF10B981).withAlpha(160),
                                blurRadius: 6,
                                spreadRadius: 0.5,
                                offset: const Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
