import 'package:flutter/material.dart';

import '../controllers/flow_controller.dart';
import '../services/sync_engine.dart';
import '../services/sync_status.dart';

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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Gateway Cloud Sync',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Color(0xFF0F172A)),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFF1F5F9)),
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
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF059669), strokeWidth: 3),
              SizedBox(height: 20),
              Text(
                'Initializing Encrypted Payload...',
                style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 6),
              Text(
                'Compressing declarations and verifying cryptographic hashes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
              ),
            ],
          ),
        ),
      SyncUploading(:final step, :final totalSteps, :final label) => Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C0F172A),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: const Icon(Icons.cloud_upload_rounded, color: Color(0xFF059669), size: 40),
              ),
              const SizedBox(height: 20),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.2),
              ),
              const SizedBox(height: 6),
              Text(
                'Phase $step of $totalSteps • Multipart Secure Stream',
                style: const TextStyle(color: Color(0xFF059669), fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: totalSteps > 0 ? step / totalSteps : 0.5,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
                ),
              ),
            ],
          ),
        ),
      SyncSucceeded() => Container(
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFA7F3D0), width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1410B981),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Banner with Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F172A),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(26),
                    topRight: Radius.circular(26),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withAlpha(40),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF10B981).withAlpha(100)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 13),
                          SizedBox(width: 5),
                          Text(
                            'TRANSACTION COMMITTED',
                            style: TextStyle(
                              color: Color(0xFF34D399),
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
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Spring Animated Icon
                    ScaleTransition(
                      scale: _scaleAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFA7F3D0), width: 2.5),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x2010B981),
                              blurRadius: 18,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 52),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Registration Committed!',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.controller.manifest.title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF059669),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'All customer declarations, Fayda ID tokens, biometric photos, and digital signatures are cryptographically sealed in the core banking ledger.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5, height: 1.45),
                    ),
                    const SizedBox(height: 20),

                    // Audit Checklist Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          _buildAuditRow(Icons.fingerprint_rounded, 'Fayda ID Verified & Tokenized'),
                          const Divider(height: 14, color: Color(0xFFE2E8F0)),
                          _buildAuditRow(Icons.badge_outlined, 'National ID Media Stored'),
                          const Divider(height: 14, color: Color(0xFFE2E8F0)),
                          _buildAuditRow(Icons.draw_rounded, 'Legal Signatory Hash Sealed'),
                          const Divider(height: 14, color: Color(0xFFE2E8F0)),
                          _buildAuditRow(Icons.cloud_done_rounded, 'Core Banking Ledger Synced'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Back to Terminal Dashboard Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 3,
                          shadowColor: const Color(0x40059669),
                        ),
                        icon: const Icon(Icons.home_filled, size: 20),
                        label: const Text(
                          'Back to Terminal Dashboard',
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFECACA)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x10DC2626),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 48),
              ),
              const SizedBox(height: 20),
              const Text(
                'Sync Encountered An Error',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
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
        Icon(icon, size: 16, color: const Color(0xFF059669)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ),
        const Icon(Icons.check_rounded, size: 16, color: Color(0xFF059669)),
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
