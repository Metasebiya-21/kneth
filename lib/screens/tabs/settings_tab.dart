import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class SettingsTab extends StatelessWidget {
  final int activeDraftCount;
  final VoidCallback onForceSync;
  final VoidCallback onOpenGatewayConfig;

  const SettingsTab({
    super.key,
    required this.activeDraftCount,
    required this.onForceSync,
    required this.onOpenGatewayConfig,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          // Header
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Configure your terminal',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 24),

          // ── Agent Profile ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: AppColors.cardDecoration,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.primaryGradient,
                  ),
                  child: const CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.surface,
                    child: Icon(Icons.person_rounded, color: AppColors.primary, size: 28),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Abebe Kebede', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
                      SizedBox(height: 2),
                      Text('Field Agent — Addis Ababa', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Active',
                    style: TextStyle(color: AppColors.success, fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Gateway & Network ──────────────────────────────────────
          _sectionHeader('Gateway & Network'),
          const SizedBox(height: 10),
          Container(
            decoration: AppColors.cardDecoration,
            child: Column(
              children: [
                _settingsTile(
                  icon: Icons.dns_rounded,
                  iconColor: AppColors.primary,
                  title: 'Backend Gateway',
                  subtitle: 'Server address & presets',
                  onTap: onOpenGatewayConfig,
                ),
                const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                _settingsTile(
                  icon: Icons.sync_rounded,
                  iconColor: AppColors.secondary,
                  title: 'Force Sync',
                  subtitle: 'Refresh catalog & check drafts',
                  onTap: onForceSync,
                ),
                const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                _settingsTile(
                  icon: Icons.wifi_tethering_rounded,
                  iconColor: AppColors.success,
                  title: 'Network Diagnostics',
                  subtitle: 'Test server connectivity',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Running diagnostics...')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Storage & Data ─────────────────────────────────────────
          _sectionHeader('Storage & Data'),
          const SizedBox(height: 10),
          Container(
            decoration: AppColors.cardDecoration,
            child: Column(
              children: [
                _settingsTile(
                  icon: Icons.storage_rounded,
                  iconColor: AppColors.accentViolet,
                  title: 'Local Storage',
                  subtitle: '$activeDraftCount saved drafts',
                  trailing: _storageUsageMeter(),
                ),
                const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                _settingsTile(
                  icon: Icons.photo_library_rounded,
                  iconColor: AppColors.accentAmber,
                  title: 'Media Cache',
                  subtitle: 'Captured photos & signatures',
                ),
                const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                _settingsTile(
                  icon: Icons.delete_sweep_rounded,
                  iconColor: AppColors.error,
                  title: 'Clear All Data',
                  subtitle: 'Remove saved drafts & cache',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Clear data not implemented yet.')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── About ──────────────────────────────────────────────────
          _sectionHeader('About'),
          const SizedBox(height: 10),
          Container(
            decoration: AppColors.cardDecoration,
            child: Column(
              children: [
                _settingsTile(
                  icon: Icons.info_outline_rounded,
                  iconColor: AppColors.textSecondary,
                  title: 'Version',
                  subtitle: 'Kifiya Terminal v2.0.0',
                ),
                const Divider(height: 1, indent: 56, color: AppColors.borderSubtle),
                _settingsTile(
                  icon: Icons.shield_outlined,
                  iconColor: AppColors.textSecondary,
                  title: 'Security & Privacy',
                  subtitle: 'End-to-end encrypted data handling',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Footer
          const Center(
            child: Column(
              children: [
                Text(
                  'Kifiya Financial Technologies',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2),
                Text(
                  'Server-Driven UI Client for Agent Workflows',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.textMuted,
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withAlpha(20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                  const SizedBox(height: 1),
                  Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null)
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _storageUsageMeter() {
    return SizedBox(
      width: 48,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('12%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 0.12,
              minHeight: 4,
              backgroundColor: AppColors.surfaceDim,
              valueColor: AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}
