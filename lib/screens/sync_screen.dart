import 'package:flutter/material.dart';

import '../controllers/flow_controller.dart';
import '../services/sync_engine.dart';
import '../services/sync_status.dart';
import '../theme/app_colors.dart';

class SyncScreen extends StatefulWidget {
  final FlowController controller;

  const SyncScreen({super.key, required this.controller});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> with SingleTickerProviderStateMixin {
  late final SyncEngine _engine = SyncEngine(apiClient: widget.controller.apiClient);
  SyncStatus _status = const SyncIdle();
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );
    _start();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _start() {
    final values = widget.controller.allValues;
    final mediaFilePaths = values.entries
        .where((entry) => entry.key.endsWith('.filePath') && entry.value != null)
        .map((entry) => entry.value as String)
        .toList();

    _engine.sync(values: values, mediaFilePaths: mediaFilePaths).listen((status) async {
      if (!mounted) return;
      setState(() => _status = status);
      if (status is SyncSucceeded) {
        _animController.forward(from: 0.0);
        await widget.controller.clearSaved();
      }
    });
  }

  void _retry() {
    setState(() => _status = const SyncIdle());
    _start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cloud Sync', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: AppColors.border),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey(_status.runtimeType),
              child: _buildBody(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final status = _status;
    return switch (status) {
      SyncIdle() => Container(
          padding: const EdgeInsets.all(32),
          decoration: AppColors.cardDecorationElevated,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
              SizedBox(height: 20),
              Text(
                'Preparing Encrypted Payload...',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 6),
              Text(
                'Compressing declarations and verifying cryptographic hashes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            ],
          ),
        ),
      SyncUploading(:final step, :final totalSteps, :final label) => Container(
          padding: const EdgeInsets.all(28),
          decoration: AppColors.cardDecorationElevated,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary.withAlpha(50)),
                ),
                child: const Icon(Icons.cloud_upload_rounded, color: AppColors.primary, size: 40),
              ),
              const SizedBox(height: 20),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.2),
              ),
              const SizedBox(height: 6),
              Text(
                'Phase $step of $totalSteps • Secure Stream',
                style: const TextStyle(color: AppColors.primary, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: totalSteps > 0 ? step / totalSteps : 0.5,
                  minHeight: 8,
                  backgroundColor: AppColors.surfaceDim,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      SyncSucceeded() => Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: AppColors.cardDecorationElevated,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.white, size: 13),
                          SizedBox(width: 5),
                          Text(
                            'COMMITTED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _formattedTimestamp(),
                      style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.success.withAlpha(60), width: 2.5),
                        ),
                        child: const Icon(Icons.verified_rounded, color: AppColors.success, size: 52),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Registration Committed!',
                      style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.controller.manifest.title,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'All declarations, ID tokens, biometrics, and signatures are sealed in the core banking ledger.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.45),
                    ),
                    const SizedBox(height: 20),

                    // Audit Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDim,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          _buildAuditRow(Icons.fingerprint_rounded, 'Fayda ID Verified & Tokenized'),
                          Divider(height: 14, color: AppColors.border.withAlpha(100)),
                          _buildAuditRow(Icons.badge_outlined, 'National ID Media Stored'),
                          Divider(height: 14, color: AppColors.border.withAlpha(100)),
                          _buildAuditRow(Icons.draw_rounded, 'Legal Signatory Hash Sealed'),
                          Divider(height: 14, color: AppColors.border.withAlpha(100)),
                          _buildAuditRow(Icons.cloud_done_rounded, 'Core Banking Ledger Synced'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.home_filled, size: 20),
                        label: const Text(
                          'Back to Dashboard',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      SyncFailed(:final message) => Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.error.withAlpha(40)),
            boxShadow: const [
              BoxShadow(color: AppColors.shadowMedium, blurRadius: 20, offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.errorLight,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.error.withAlpha(40)),
                ),
                child: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
              ),
              const SizedBox(height: 20),
              const Text(
                'Sync Encountered An Error',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry Synchronization', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _retry,
                ),
              ),
            ],
          ),
        ),
    };
  }

  Widget _buildAuditRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ),
        const Icon(Icons.check_rounded, size: 16, color: AppColors.success),
      ],
    );
  }

  static String _formattedTimestamp() {
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$min';
  }
}
