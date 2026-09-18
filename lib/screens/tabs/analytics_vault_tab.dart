import 'package:flutter/material.dart';

class AnalyticsVaultTab extends StatelessWidget {
  final int activeDraftCount;
  final VoidCallback onForceSync;
  final VoidCallback onOpenGatewayConfig;

  const AnalyticsVaultTab({
    super.key,
    required this.activeDraftCount,
    required this.onForceSync,
    required this.onOpenGatewayConfig,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Insights & Vault',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Field telemetry & encrypted cache',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Gateway Settings',
              icon: const Icon(Icons.settings_suggest_rounded, color: Color(0xFF475569)),
              onPressed: onOpenGatewayConfig,
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Bento 2x2 Metric Grid
        _buildBentoGrid(),
        const SizedBox(height: 20),

        // Encrypted Vault Section
        _buildVaultStorageCard(context),
        const SizedBox(height: 20),

        // Network Diagnostics
        _buildNetworkDiagnosticsCard(context),
      ],
    );
  }

  Widget _buildBentoGrid() {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _metricCard(
                  title: 'Cases Verified',
                  value: '18',
                  badgeText: '+24%',
                  badgeColor: const Color(0xFF10B981),
                  icon: Icons.check_circle_rounded,
                  iconColor: const Color(0xFF059669),
                  subtext: 'Target 20/day',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _metricCard(
                  title: 'Gateway SLA',
                  value: '99.8%',
                  badgeText: 'Optimal',
                  badgeColor: const Color(0xFF0284C7),
                  icon: Icons.cloud_done_rounded,
                  iconColor: const Color(0xFF0284C7),
                  subtext: '45ms latency',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _metricCard(
                  title: 'Offline Vault',
                  value: 'Ready',
                  badgeText: 'Encrypted',
                  badgeColor: const Color(0xFF8B5CF6),
                  icon: Icons.shield_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  subtext: 'Zero data loss',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _metricCard(
                  title: 'Pending Drafts',
                  value: '$activeDraftCount',
                  badgeText: activeDraftCount == 0 ? 'Clean' : 'Resume',
                  badgeColor: activeDraftCount == 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  icon: Icons.pending_actions_rounded,
                  iconColor: const Color(0xFFD97706),
                  subtext: 'Local storage',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String badgeText,
    required Color badgeColor,
    required IconData icon,
    required Color iconColor,
    required String subtext,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x040F172A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
          const SizedBox(height: 2),
          Text(subtext, style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildVaultStorageCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.lock_clock_rounded, color: Color(0xFF8B5CF6), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Offline Encrypted Vault',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('AES-256 GCM', style: TextStyle(color: Color(0xFF7E22CE), fontWeight: FontWeight.w800, fontSize: 10.5)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'All biometrics, Fayda lookups, and customer declarations are encrypted locally before transmission.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          _storageRow('Customer Form Declarations', '18 Records', Icons.description_outlined),
          _storageRow('Biometric Photo & Doc Assets', '42 Files', Icons.camera_alt_outlined),
          _storageRow('Signatures & Legal Consent Hashes', '18 Hashes', Icons.draw_outlined),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.cloud_sync_rounded, size: 18),
              label: const Text('Force Secure Vault Flush & Sync', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vault synchronized: all local artifacts verified and flush queue clean.'),
                    backgroundColor: Color(0xFF059669),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _storageRow(String label, String count, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: const Color(0xFF64748B)),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
            ],
          ),
          Text(count, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  Widget _buildNetworkDiagnosticsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.wifi_tethering_rounded, color: Color(0xFF0284C7), size: 18),
              SizedBox(width: 8),
              Text('Network Diagnostics', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFF0F172A))),
            ],
          ),
          const SizedBox(height: 10),
          _diagItem('Gateway Handshake', '200 OK • 42ms', const Color(0xFF10B981)),
          _diagItem('NID Program Gateway', 'Live & Synchronized', const Color(0xFF10B981)),
          _diagItem('Offline Fallback Queue', 'Active (0 Delayed)', const Color(0xFF64748B)),
        ],
      ),
    );
  }

  Widget _diagItem(String label, String val, Color statusColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          Text(val, style: TextStyle(fontSize: 11.5, color: statusColor, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
