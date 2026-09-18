import 'package:flutter/material.dart';

import '../../controllers/flow_controller.dart';
import '../../models/flow_manifest.dart';

class TerminalHomeTab extends StatefulWidget {
  final List<FlowManifest> flows;
  final Map<String, FlowController> activeDrafts;
  final Function(FlowManifest) onStartFlow;
  final Function(FlowController) onResumeFlow;
  final Function(FlowController) onDiscardDraft;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenCatalog;
  final VoidCallback onOpenGatewayConfig;

  const TerminalHomeTab({
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
  State<TerminalHomeTab> createState() => _TerminalHomeTabState();
}

class _TerminalHomeTabState extends State<TerminalHomeTab> with SingleTickerProviderStateMixin {
  late AnimationController _beaconController;
  late Animation<double> _beaconScale;

  @override
  void initState() {
    super.initState();
    _beaconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _beaconScale = Tween<double>(begin: 0.85, end: 1.25).animate(
      CurvedAnimation(parent: _beaconController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _beaconController.dispose();
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      children: [
        // Luxury Obsidian Hero Header
        _buildLuxuryHeroHeader(),
        const SizedBox(height: 18),

        // In-Progress Draft Spotlight Card
        if (topDraft != null) ...[
          _buildDraftSpotlight(topDraft),
          const SizedBox(height: 18),
        ],

        // Launchpad Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Row(
              children: [
                Icon(Icons.bolt_rounded, size: 20, color: Color(0xFF34D399)),
                SizedBox(width: 6),
                Text(
                  'Field Launchpad',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE2E8F0),
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: widget.onOpenCatalog,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Text(
                      'All Workflows',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFF34D399)),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.arrow_forward_ios_rounded, size: 11, color: Color(0xFF34D399)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Premium 2x2 Glass Launchpad Grid
        _buildPremiumLaunchpadGrid(),
        const SizedBox(height: 20),

        // Milestone Goal Ring Card
        _buildMilestoneGoalCard(),
        const SizedBox(height: 20),

        // Recent Activity Feed
        _buildRecentActivitySection(),
      ],
    );
  }

  Widget _buildLuxuryHeroHeader() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0B132B), // Deep Obsidian
            Color(0xFF1C2541), // Midnight Sapphire
            Color(0xFF0F172A),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withAlpha(25), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330B132B),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Background ambient sheen
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF10B981).withAlpha(45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [Color(0xFF10B981), Color(0xFF34D399)],
                              ),
                            ),
                            child: const CircleAvatar(
                              radius: 21,
                              backgroundColor: Color(0xFF1E293B),
                              child: Icon(Icons.person_rounded, color: Colors.white, size: 24),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_getGreeting()},',
                                  style: TextStyle(
                                    color: Colors.white.withAlpha(160),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Text(
                                  'Abebe Kebede',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
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
                    const SizedBox(width: 8),
                    // Live Status Badge with Animated Pulsing Beacon
                    GestureDetector(
                      onTap: widget.onOpenGatewayConfig,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withAlpha(35),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF10B981).withAlpha(100)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ScaleTransition(
                              scale: _beaconScale,
                              child: const Icon(Icons.fiber_manual_record_rounded, size: 10, color: Color(0xFF34D399)),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'FIELD ONLINE',
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
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(Icons.verified_rounded, size: 16, color: Color(0xFF10B981)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Addis Ababa Field Station • Kifiya Verified Terminal',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftSpotlight(FlowController draft) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFB45309).withAlpha(140), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7).withAlpha(25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.edit_note_rounded, color: Color(0xFFFBBF24), size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7).withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('DRAFT IN PROGRESS', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFFFBBF24))),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  draft.manifest.title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFFE2E8F0)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text('Paused at ${draft.progressLabel}', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF94A3B8), size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: () => widget.onDiscardDraft(draft),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF34D399),
              foregroundColor: const Color(0xFF06281B),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
            onPressed: () => widget.onResumeFlow(draft),
            child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumLaunchpadGrid() {
    final catalog = widget.flows.isNotEmpty ? widget.flows : FlowManifest.defaultCatalog;

    final individualKyc = catalog.firstWhere((f) => f.flowId == 'kyc_kyb_collection', orElse: () => catalog[0]);
    final merchantKyb = catalog.firstWhere((f) => f.flowId == 'merchant_kyb', orElse: () => catalog[1]);
    final agriCredit = catalog.firstWhere((f) => f.flowId == 'agri_loan_onboarding', orElse: () => catalog[2]);
    final faydaFast = catalog.firstWhere((f) => f.flowId == 'fayda_fast_track', orElse: () => catalog.last);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _premiumLaunchpadCard(
                title: 'Individual KYC',
                subtitle: 'National ID & Biometrics',
                tag: '⚡ 4 STAGES',
                tagBg: const Color(0xFF064E3B),
                tagColor: const Color(0xFF6EE7B7),
                icon: Icons.person_add_alt_1_rounded,
                tintGradient: [const Color(0xFF032E22), const Color(0xFF111827)],
                borderHighlight: const Color(0xFF065F46),
                iconGradient: const [Color(0xFF059669), Color(0xFF10B981)],
                onTap: () => widget.onStartFlow(individualKyc),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _premiumLaunchpadCard(
                title: 'Merchant KYB',
                subtitle: 'Trade License & VAT',
                tag: '🏢 4 STAGES',
                tagBg: const Color(0xFF082F49),
                tagColor: const Color(0xFF7DD3FC),
                icon: Icons.storefront_rounded,
                tintGradient: [const Color(0xFF082F49), const Color(0xFF111827)],
                borderHighlight: const Color(0xFF075985),
                iconGradient: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
                onTap: () => widget.onStartFlow(merchantKyb),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _premiumLaunchpadCard(
                title: 'Agri-Credit',
                subtitle: 'Farmer Cooperative',
                tag: '🌱 FAST TRACK',
                tagBg: const Color(0xFF052E16),
                tagColor: const Color(0xFF86EFAC),
                icon: Icons.agriculture_rounded,
                tintGradient: [const Color(0xFF052E16), const Color(0xFF111827)],
                borderHighlight: const Color(0xFF166534),
                iconGradient: const [Color(0xFF16A34A), Color(0xFF4ADE80)],
                onTap: () => widget.onStartFlow(agriCredit),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _premiumLaunchpadCard(
                title: 'Fayda Fast',
                subtitle: 'Instant NID Lookup',
                tag: '🔥 INSTANT',
                tagBg: const Color(0xFF451A03),
                tagColor: const Color(0xFFFCD34D),
                icon: Icons.flash_on_rounded,
                tintGradient: [const Color(0xFF451A03), const Color(0xFF111827)],
                borderHighlight: const Color(0xFF92400E),
                iconGradient: const [Color(0xFFD97706), Color(0xFFFBBF24)],
                onTap: () => widget.onStartFlow(faydaFast),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _premiumLaunchpadCard({
    required String title,
    required String subtitle,
    required String tag,
    required Color tagBg,
    required Color tagColor,
    required IconData icon,
    required List<Color> tintGradient,
    required Color borderHighlight,
    required List<Color> iconGradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: tintGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderHighlight, width: 1.2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x060F172A),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: iconGradient),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: iconGradient.first.withAlpha(70),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: tagBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      color: tagColor,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFFE2E8F0), letterSpacing: -0.2),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMilestoneGoalCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Circular Progress Ring Gauge
          const SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: 0.9,
                  strokeWidth: 6,
                  backgroundColor: Color(0xFF334155),
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                  strokeCap: StrokeCap.round,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '90%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFE2E8F0),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Milestone details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Text(
                      'Daily Verified Goal',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Color(0xFFE2E8F0),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  '18 of 20 Cases Completed',
                  style: TextStyle(color: Color(0xFF34D399), fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7).withAlpha(25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '🎯 2 more to complete daily target bonus',
                    style: TextStyle(color: Color(0xFFFBBF24), fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Recent Synced Cases',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Color(0xFFE2E8F0)),
            ),
            InkWell(
              onTap: widget.onOpenHistory,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text('View All Records', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF94A3B8))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF334155)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              _recentCardRow('Dawit Alemu', 'Individual KYC', '12 mins ago', '#KIF-8821', false),
              _recentCardRow('Selam Grocery PLC', 'Merchant KYB', '45 mins ago', '#KIF-8820', true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recentCardRow(String name, String type, String time, String id, bool isLast) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFF334155))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF064E3B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFFE2E8F0))),
                const SizedBox(height: 2),
                Text('$type • $time', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(id, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFFCBD5E1))),
          ),
        ],
      ),
    );
  }
}
