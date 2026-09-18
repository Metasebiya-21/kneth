import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A clean, modern step progress header for flow screens.
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
          color: AppColors.surface,
          border: Border(
            bottom: BorderSide(color: AppColors.border, width: 1),
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
                    icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary, size: 22),
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
                          color: AppColors.textMuted,
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
                          color: AppColors.textPrimary,
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
                // Step counter pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withAlpha(50)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.bolt_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Step $currentStep of $effectiveTotal',
                        style: const TextStyle(
                          color: AppColors.primary,
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

            // Segmented Progress Bars
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
                      gradient: (isCompleted || isCurrent) ? AppColors.primaryGradient : null,
                      color: (isCompleted || isCurrent) ? null : AppColors.surfaceContainer,
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withAlpha(100),
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
