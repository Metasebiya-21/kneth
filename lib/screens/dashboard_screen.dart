import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/flow_controller.dart';
import '../models/flow_manifest.dart';
import '../services/api_client.dart';
import 'flow_screen.dart';

class DashboardScreen extends StatefulWidget {
  final ApiClient? apiClient;

  const DashboardScreen({super.key, this.apiClient});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  late ApiClient _apiClient;
  String _baseUrl = 'https://api.kifiya.et';

  List<FlowManifest> _flows = [];
  Map<String, FlowController> _activeDrafts = {};
  String _selectedCategory = 'All';
  String _searchQuery = '';
  bool _isLoadingCatalog = true;

  late AnimationController _staggerController;
  late AnimationController _beaconController;
  late Animation<double> _beaconScale;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _beaconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _beaconScale = Tween<double>(begin: 0.85, end: 1.25).animate(
      CurvedAnimation(parent: _beaconController, curve: Curves.easeInOut),
    );

    _initApiClient();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _beaconController.dispose();
    super.dispose();
  }

  Future<void> _initApiClient() async {
    _baseUrl = await HttpApiClient.getSavedBaseUrl();
    _apiClient = widget.apiClient ?? HttpApiClient(baseUrl: _baseUrl);
    await _loadCatalogAndDrafts();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _loadCatalogAndDrafts() async {
    setState(() => _isLoadingCatalog = true);
    await Future.wait([
      _fetchFlowCatalog(),
      _checkDrafts(),
    ]);
    if (mounted) {
      setState(() => _isLoadingCatalog = false);
    }
  }

  Future<void> _fetchFlowCatalog() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('cached_flow_catalog');
    if (cached != null) {
      try {
        final List decoded = jsonDecode(cached);
        final list = decoded.map((e) => FlowManifest.fromJson(e as Map<String, dynamic>)).toList();
        if (mounted && list.isNotEmpty) {
          setState(() => _flows = list);
        }
      } catch (_) {}
    }

    try {
      final remoteList = await _apiClient.fetchAvailableFlows();
      if (mounted && remoteList.isNotEmpty) {
        setState(() => _flows = remoteList);
        await prefs.setString(
          'cached_flow_catalog',
          jsonEncode(remoteList.map((m) => m.toJson()).toList()),
        );
      }
    } catch (_) {
      if (_flows.isEmpty) {
        setState(() => _flows = FlowManifest.defaultCatalog);
      }
    }
  }

  Future<void> _checkDrafts() async {
    final drafts = <String, FlowController>{};
    final catalog = _flows.isNotEmpty ? _flows : FlowManifest.defaultCatalog;

    for (final manifest in catalog) {
      final restored = await FlowController.restore(
        manifest: manifest,
        apiClient: _apiClient,
      );
      if (restored != null && !restored.isComplete && restored.hasCollectedData) {
        drafts[manifest.flowId] = restored;
      }
    }
    if (mounted) {
      setState(() => _activeDrafts = drafts);
    }
  }

  void _startFlow(FlowManifest manifest) {
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => FlowScreen(
              controller: FlowController(manifest: manifest, apiClient: _apiClient),
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.easeInOutCubic;
              final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
              return SlideTransition(position: animation.drive(tween), child: child);
            },
          ),
        )
        .then((_) => _checkDrafts());
  }

  void _resumeFlow(FlowController controller) {
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => FlowScreen(controller: controller),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              const begin = Offset(1.0, 0.0);
              const end = Offset.zero;
              const curve = Curves.easeInOutCubic;
              final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
              return SlideTransition(position: animation.drive(tween), child: child);
            },
          ),
        )
        .then((_) => _checkDrafts());
  }

  Future<void> _discardDraft(FlowController controller) async {
    await controller.clearSaved();
    await _checkDrafts();
  }

  void _showBackendConfigSheet() {
    final controller = TextEditingController(text: _baseUrl);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(Icons.dns_rounded, color: Color(0xFF059669), size: 24),
                        SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'SDUI Backend Gateway',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a preset gateway endpoint or enter your live server address for dynamic stage schemas.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),

              // Presets
              Wrap(
                spacing: 8,
                children: [
                  _gatewayChip('Production', 'https://api.kifiya.et', controller),
                  _gatewayChip('Staging', 'https://staging.kifiya.et', controller),
                  _gatewayChip('Local Wi-Fi ADB', 'http://192.168.8.9:8080', controller),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: controller,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                decoration: InputDecoration(
                  labelText: 'Active Base URL',
                  hintText: 'https://api.kifiya.et',
                  prefixIcon: const Icon(Icons.link_rounded, color: Color(0xFF059669)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF059669), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 3,
                  ),
                  onPressed: () async {
                    final newUrl = controller.text.trim();
                    if (newUrl.isNotEmpty) {
                      final nav = Navigator.of(context);
                      await HttpApiClient.saveBaseUrl(newUrl);
                      if (!mounted) return;
                      setState(() {
                        _baseUrl = newUrl;
                        _apiClient = HttpApiClient(baseUrl: newUrl);
                      });
                      nav.pop();
                      await _loadCatalogAndDrafts();
                    }
                  },
                  child: const Text('Save & Reconnect Gateway', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _gatewayChip(String label, String url, TextEditingController controller) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      backgroundColor: const Color(0xFFF1F5F9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onPressed: () => setState(() => controller.text = url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allFlows = _flows.isNotEmpty ? _flows : FlowManifest.defaultCatalog;
    final categories = ['All', ...allFlows.map((e) => e.category).toSet()];

    final filteredFlows = allFlows.where((flow) {
      final matchesCat = _selectedCategory == 'All' || flow.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          flow.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          flow.description.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCat && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: GestureDetector(
          onLongPress: _showBackendConfigSheet,
          behavior: HitTestBehavior.opaque,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF10B981)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x22059669),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Kifiya Terminal',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16.5,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Server-Driven Field Engine',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Flows',
            icon: _isLoadingCatalog
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF059669)),
                  )
                : const Icon(Icons.sync_rounded, color: Color(0xFF475569)),
            onPressed: _loadCatalogAndDrafts,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF059669),
        onRefresh: () async {
          _staggerController.reset();
          _staggerController.forward();
          await _loadCatalogAndDrafts();
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          children: [
            _staggeredItem(0, _buildRevolutObsidianHeader(theme)),
            const SizedBox(height: 18),
            _staggeredItem(1, _buildQuickActionIconsRow(allFlows)),
            const SizedBox(height: 20),
            _staggeredItem(2, _buildStripeMetricsGrid(theme)),
            const SizedBox(height: 22),
            if (_activeDrafts.isNotEmpty) ...[
              _staggeredItem(2, _buildDraftsSection(theme)),
              const SizedBox(height: 24),
            ],
            _staggeredItem(3, _buildSearchAndFilters(categories.toList(), theme)),
            const SizedBox(height: 18),
            _staggeredItem(3, _buildWorkflowsList(filteredFlows, theme)),
            const SizedBox(height: 26),
            _staggeredItem(4, _buildRecentSubmissionsSection(theme)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _staggeredItem(int index, Widget child) {
    final start = (index * 0.12).clamp(0.0, 0.7);
    final end = (start + 0.45).clamp(0.0, 1.0);
    final animation = CurvedAnimation(
      parent: _staggerController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );

    return AnimatedBuilder(
      animation: _staggerController,
      builder: (context, _) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, (1.0 - animation.value) * 16),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildRevolutObsidianHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330F172A),
            blurRadius: 20,
            offset: Offset(0, 10),
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
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF10B981), width: 2),
                      ),
                      child: const CircleAvatar(
                        radius: 20,
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
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Text(
                            'Abebe Kebede',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.2,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withAlpha(35),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981).withAlpha(90)),
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
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
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
    );
  }

  Widget _buildQuickActionIconsRow(List<FlowManifest> allFlows) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _quickActionPill(
            icon: Icons.person_add_alt_1_rounded,
            label: 'Individual KYC',
            gradient: const [Color(0xFF059669), Color(0xFF10B981)],
            onTap: () {
              final flow = allFlows.firstWhere(
                (f) => f.flowId == 'kyc_kyb_collection',
                orElse: () => allFlows.first,
              );
              _startFlow(flow);
            },
          ),
          const SizedBox(width: 12),
          _quickActionPill(
            icon: Icons.storefront_rounded,
            label: 'Merchant KYB',
            gradient: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
            onTap: () {
              final flow = allFlows.firstWhere(
                (f) => f.flowId == 'merchant_kyb',
                orElse: () => allFlows.first,
              );
              _startFlow(flow);
            },
          ),
          const SizedBox(width: 12),
          _quickActionPill(
            icon: Icons.agriculture_rounded,
            label: 'Agri-Credit',
            gradient: const [Color(0xFF43A047), Color(0xFF66BB6A)],
            onTap: () {
              final flow = allFlows.firstWhere(
                (f) => f.flowId == 'agri_loan_onboarding',
                orElse: () => allFlows.first,
              );
              _startFlow(flow);
            },
          ),
          const SizedBox(width: 12),
          _quickActionPill(
            icon: Icons.flash_on_rounded,
            label: 'Fayda Fast',
            gradient: const [Color(0xFFD97706), Color(0xFFFBBF24)],
            onTap: () {
              final flow = allFlows.firstWhere(
                (f) => f.flowId == 'fayda_fast_track',
                orElse: () => allFlows.first,
              );
              _startFlow(flow);
            },
          ),
        ],
      ),
    );
  }

  Widget _quickActionPill({
    required IconData icon,
    required String label,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x060F172A),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: gradient),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0F172A)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStripeMetricsGrid(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Performance & Sync Status',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.3,
              ),
            ),
            Text(
              'Today',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _bentoMetricCard(
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
                child: _bentoMetricCard(
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
                child: _bentoMetricCard(
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
                child: _bentoMetricCard(
                  title: 'Pending Drafts',
                  value: '${_activeDrafts.length}',
                  badgeText: _activeDrafts.isEmpty ? 'Clean' : 'Resume',
                  badgeColor: _activeDrafts.isEmpty ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
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

  Widget _bentoMetricCard({
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
        borderRadius: BorderRadius.circular(18),
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
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
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
          Text(
            title,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.history_rounded, size: 20, color: Color(0xFFD97706)),
                SizedBox(width: 6),
                Text(
                  'In-Progress Registration Drafts',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_activeDrafts.length} Saved',
                style: const TextStyle(color: Color(0xFFB45309), fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._activeDrafts.entries.map((entry) {
          final ctrl = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFDE68A)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x060F172A),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: Color(0xFFD97706), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ctrl.manifest.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Paused at ${ctrl.progressLabel}',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF94A3B8), size: 20),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      onPressed: () => _discardDraft(ctrl),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _resumeFlow(ctrl),
                      child: const Text('Resume', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSearchAndFilters(List<String> categories, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Live Search Bar
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x040F172A),
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            decoration: InputDecoration(
              hintText: 'Search workflows (KYC, KYB, Fayda, Loan)...',
              hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => setState(() => _searchQuery = ''),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedCategory = cat),
                  selectedColor: const Color(0xFF0F172A),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF475569),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkflowsList(List<FlowManifest> flows, ThemeData theme) {
    if (flows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Column(
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
            SizedBox(height: 12),
            Text(
              'No workflows match your search',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
            ),
            SizedBox(height: 4),
            Text('Try selecting a different category or clearing search filters.', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Available Workflow Catalog',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
            ),
            Text(
              '${flows.length} ready',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...flows.map((flow) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
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
            child: InkWell(
              onTap: () => _startFlow(flow),
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _getCategoryGradient(flow.category),
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(_getCategoryIcon(flow.category), color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                flow.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                flow.description,
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 1.35),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: Text(
                            flow.category.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFF047857),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Text(
                                flow.estimatedDuration,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Icon(Icons.layers_outlined, size: 12, color: Color(0xFF64748B)),
                              const SizedBox(width: 4),
                              Text(
                                '${flow.stageCount} Stages',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRecentSubmissionsSection(ThemeData theme) {
    final recentCases = [
      {'name': 'Dawit Alemu', 'type': 'Individual KYC', 'time': '12 mins ago', 'status': 'Synced', 'id': '#KIF-8821'},
      {'name': 'Selam Grocery PLC', 'type': 'Merchant KYB', 'time': '45 mins ago', 'status': 'Synced', 'id': '#KIF-8820'},
      {'name': 'Marta Tadesse', 'type': 'Fayda Lookup', 'time': '2 hours ago', 'status': 'Verified', 'id': '#KIF-8819'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Field Registrations',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
            ),
            Text(
              'Audit Log',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
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
            children: recentCases.asMap().entries.map((entry) {
              final index = entry.key;
              final c = entry.value;
              final isLast = index == recentCases.length - 1;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            c['name']!,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF0F172A)),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${c['type']} • ${c['time']}',
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        c['id']!,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Color(0xFF475569)),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  List<Color> _getCategoryGradient(String category) {
    switch (category.toLowerCase()) {
      case 'kyc':
      case 'personal':
      case 'individuals':
        return [const Color(0xFF059669), const Color(0xFF10B981)];
      case 'kyb':
      case 'merchant':
      case 'enterprises':
        return [const Color(0xFF0284C7), const Color(0xFF38BDF8)];
      case 'lending':
      case 'loans':
      case 'agri-finance':
        return [const Color(0xFF43A047), const Color(0xFF66BB6A)];
      case 'verification':
      case 'identity':
        return [const Color(0xFFD97706), const Color(0xFFFBBF24)];
      default:
        return [const Color(0xFF0F172A), const Color(0xFF334155)];
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'kyc':
      case 'personal':
      case 'individuals':
        return Icons.badge_rounded;
      case 'kyb':
      case 'merchant':
      case 'enterprises':
        return Icons.store_rounded;
      case 'lending':
      case 'loans':
      case 'agri-finance':
        return Icons.agriculture_rounded;
      case 'verification':
      case 'identity':
        return Icons.fingerprint_rounded;
      default:
        return Icons.dynamic_form_rounded;
    }
  }
}
