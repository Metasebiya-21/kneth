import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/flow_controller.dart';
import '../models/flow_manifest.dart';
import '../services/api_client.dart';
import 'flow_screen.dart';
import 'tabs/analytics_vault_tab.dart';
import 'tabs/case_history_tab.dart';
import 'tabs/terminal_home_tab.dart';
import 'tabs/workflow_catalog_tab.dart';

class MainNavigationShell extends StatefulWidget {
  final ApiClient? apiClient;

  const MainNavigationShell({super.key, this.apiClient});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;
  late final PageController _pageController;

  late ApiClient _apiClient;
  String _baseUrl = 'https://api.kifiya.et';

  List<FlowManifest> _flows = [];
  Map<String, FlowController> _activeDrafts = {};
  bool _isLoadingCatalog = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _initApiClient();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initApiClient() async {
    _baseUrl = await HttpApiClient.getSavedBaseUrl();
    _apiClient = widget.apiClient ?? HttpApiClient(baseUrl: _baseUrl);
    await _loadCatalogAndDrafts();
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

  void _navigateToTab(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: const Color(0xFFF8FAFC),
        titleSpacing: 18,
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
                child: const Icon(Icons.hub_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
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
                    'Server-Driven Engine',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sync Flows',
            icon: _isLoadingCatalog
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF059669)),
                  )
                : const Icon(Icons.sync_rounded, color: Color(0xFF475569), size: 22),
            onPressed: _loadCatalogAndDrafts,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageView(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (idx) => setState(() => _currentIndex = idx),
        children: [
          TerminalHomeTab(
            flows: _flows,
            activeDrafts: _activeDrafts,
            onStartFlow: _startFlow,
            onResumeFlow: _resumeFlow,
            onDiscardDraft: _discardDraft,
            onOpenHistory: () => _navigateToTab(3),
            onOpenCatalog: () => _navigateToTab(1),
            onOpenGatewayConfig: _showBackendConfigSheet,
          ),
          WorkflowCatalogTab(
            flows: _flows,
            onStartFlow: _startFlow,
            onRefresh: _loadCatalogAndDrafts,
            isLoading: _isLoadingCatalog,
          ),
          AnalyticsVaultTab(
            activeDraftCount: _activeDrafts.length,
            onForceSync: _loadCatalogAndDrafts,
            onOpenGatewayConfig: _showBackendConfigSheet,
          ),
          CaseHistoryTab(
            activeDrafts: _activeDrafts,
            onResumeFlow: _resumeFlow,
            onDiscardDraft: _discardDraft,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _buildFloatingBottomDock(),
        ),
      ),
    );
  }

  Widget _buildFloatingBottomDock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withAlpha(245),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withAlpha(25), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330F172A),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navDockItem(
            index: 0,
            icon: Icons.flash_on_rounded,
            label: 'Terminal',
          ),
          _navDockItem(
            index: 1,
            icon: Icons.layers_rounded,
            label: 'Catalog',
          ),
          _navDockItem(
            index: 2,
            icon: Icons.shield_rounded,
            label: 'Vault',
          ),
          _navDockItem(
            index: 3,
            icon: Icons.receipt_long_rounded,
            label: 'Records',
            badgeCount: _activeDrafts.isNotEmpty ? _activeDrafts.length : null,
          ),
        ],
      ),
    );
  }

  Widget _navDockItem({
    required int index,
    required IconData icon,
    required String label,
    int? badgeCount,
  }) {
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () => _navigateToTab(index),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF059669) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF059669).withAlpha(120),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : Colors.white60,
                ),
                if (badgeCount != null)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
