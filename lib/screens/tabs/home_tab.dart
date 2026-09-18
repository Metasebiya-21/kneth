import 'package:flutter/material.dart';

import '../../controllers/flow_controller.dart';
import '../../models/flow_manifest.dart';
import '../../theme/app_colors.dart';

class HomeTab extends StatefulWidget {
  final List<FlowManifest> flows;
  final Map<String, FlowController> activeDrafts;
  final Function(FlowManifest) onStartFlow;
  final Function(FlowController) onResumeFlow;
  final Function(FlowController) onDiscardDraft;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenGatewayConfig;

  const HomeTab({
    super.key,
    required this.flows,
    required this.activeDrafts,
    required this.onStartFlow,
    required this.onResumeFlow,
    required this.onDiscardDraft,
    required this.onOpenHistory,
    required this.onOpenCatalog,
    required this.onOpenGatewayConfig,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 0.9, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final hasDraft = widget.activeDrafts.isNotEmpty;
    final topDraft = hasDraft ? widget.activeDrafts.values.first : null;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          // ── Hero Welcome Card ──────────────────────────────────────
          _buildHeroCard(),
          const SizedBox(height: 20),

          // ── Quick Stats Row ────────────────────────────────────────
          _buildQuickStats(),
          const SizedBox(height: 20),

          // ── Draft Spotlight ────────────────────────────────────────
          if (topDraft != null) ...[
            _buildDraftSpotlight(topDraft),
            const SizedBox(height: 20),
          ],

          // ── Quick Actions Header ──────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              GestureDetector(
                onTap: widget.onOpenCatalog,
                child: const Text(
                  'See all',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Quick Actions Grid ─────────────────────────────────────
          _buildQuickActionsGrid(),
          const SizedBox(height: 24),

          // ── Recent Activity ────────────────────────────────────────
          _buildRecentSection(),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withAlpha(50),
            blurRadius: 24,
            offset: const Offset(0, 10),
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
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withAlpha(180), width: 2),
                      ),
                      child: const CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.white24,
                        child: Icon(Icons.person_rounded, color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _getGreeting(),
                            style: TextStyle(
                              color: Colors.white.withAlpha(200),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Text(
                            'Abebe Kebede',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
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
              // Live status
              GestureDetector(
                onTap: widget.onOpenGatewayConfig,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withAlpha(60)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ScaleTransition(
                        scale: _pulseScale,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF4ADE80),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Online',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Addis Ababa Field Station • Kifiya Verified',
                    style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 11.5, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    return Row(
      children: [
        Expanded(
          child: _statPill(
            icon: Icons.check_circle_rounded,
            iconColor: AppColors.success,
            label: 'Today',
            value: '18',
            bgColor: AppColors.successLight,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statPill(
            icon: Icons.trending_up_rounded,
            iconColor: AppColors.primary,
            label: 'Rate',
            value: '94%',
            bgColor: AppColors.primaryLight,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statPill(
            icon: Icons.pending_actions_rounded,
            iconColor: AppColors.warning,
            label: 'Drafts',
            value: '${widget.activeDrafts.length}',
            bgColor: AppColors.warningLight,
          ),
        ),
      ],
    );
  }

  Widget _statPill({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: AppColors.shadowLight, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildDraftSpotlight(FlowController draft) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warningLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.warning.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.edit_note_rounded, color: AppColors.warningDark, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'DRAFT',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.warningDark, letterSpacing: 0.5),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  draft.manifest.title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Paused at ${draft.progressLabel}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 18),
            visualDensity: VisualDensity.compact,
            onPressed: () => widget.onDiscardDraft(draft),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warningDark,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () => widget.onResumeFlow(draft),
            child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsGrid() {
    final catalog = widget.flows.isNotEmpty ? widget.flows : FlowManifest.defaultCatalog;

    final items = <_ActionItem>[
      _ActionItem('Individual\nKYC', Icons.person_add_alt_1_rounded, AppColors.emeraldGradient, AppColors.successLight,
          catalog.firstWhere((f) => f.flowId == 'kyc_kyb_collection', orElse: () => catalog[0])),
      _ActionItem('Merchant\nKYB', Icons.storefront_rounded, AppColors.skyGradient, AppColors.secondaryLight,
          catalog.firstWhere((f) => f.flowId == 'merchant_kyb', orElse: () => catalog[1])),
      _ActionItem('Agri-Credit', Icons.agriculture_rounded, AppColors.violetGradient, const Color(0xFFF5F3FF),
          catalog.firstWhere((f) => f.flowId == 'agri_loan_onboarding', orElse: () => catalog[2])),
      _ActionItem('Fayda Fast', Icons.flash_on_rounded, AppColors.amberGradient, AppColors.warningLight,
          catalog.firstWhere((f) => f.flowId == 'fayda_fast_track', orElse: () => catalog.last)),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: items.map((item) => _buildActionCard(item)).toList(),
    );
  }

  Widget _buildActionCard(_ActionItem item) {
    return InkWell(
      onTap: () => widget.onStartFlow(item.manifest),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(color: AppColors.shadowLight, blurRadius: 12, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: item.gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item.icon, color: Colors.white, size: 20),
            ),
            Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary, height: 1.25),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Activity',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3),
            ),
            GestureDetector(
              onTap: widget.onOpenHistory,
              child: const Text('View all', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.primary)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: AppColors.cardDecoration,
          child: Column(
            children: [
              _recentRow('Dawit Alemu', 'Individual KYC', '12 mins ago', '#KIF-8821', false),
              _recentRow('Selam Grocery PLC', 'Merchant KYB', '45 mins ago', '#KIF-8820', true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recentRow(String name, String type, String time, String id, bool isLast) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('$type • $time', style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceDim,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(id, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

class _ActionItem {
  final String title;
  final IconData icon;
  final LinearGradient gradient;
  final Color bgTint;
  final FlowManifest manifest;

  _ActionItem(this.title, this.icon, this.gradient, this.bgTint, this.manifest);
}
