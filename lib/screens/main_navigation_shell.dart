import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/flow_controller.dart';
import '../models/flow_manifest.dart';
import '../services/api_client.dart';
import '../theme/app_colors.dart';
import 'flow_screen.dart';
import 'tabs/home_tab.dart';
import 'tabs/workflows_tab.dart';
import 'tabs/activity_tab.dart';
import 'tabs/settings_tab.dart';

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
      backgroundColor: AppColors.surface,
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
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.dns_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Flexible(
                          child: Text(
                            'Backend Gateway',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Select a preset or enter your server address.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),

              // Presets
              Wrap(
                spacing: 8,
                children: [
                  _gatewayChip('Production', 'https://api.kifiya.et', controller),
                  _gatewayChip('Staging', 'https://staging.kifiya.et', controller),
                  _gatewayChip('Local', 'http://192.168.8.9:8080', controller),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: controller,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://api.kifiya.et',
                  prefixIcon: const Icon(Icons.link_rounded, color: AppColors.primary),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
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
                  child: const Text('Save & Reconnect', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _gatewayChip(String label, String url, TextEditingController controller) {
    final isActive = controller.text == url;
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isActive ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
      backgroundColor: isActive ? AppColors.primaryLight : AppColors.surfaceDim,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isActive ? AppColors.primary : AppColors.border),
      ),
      onPressed: () => setState(() => controller.text = url),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: PageView(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (idx) => setState(() => _currentIndex = idx),
        children: [
          HomeTab(
            flows: _flows,
            activeDrafts: _activeDrafts,
            onStartFlow: _startFlow,
            onResumeFlow: _resumeFlow,
            onDiscardDraft: _discardDraft,
            onOpenHistory: () => _navigateToTab(2),
            onOpenCatalog: () => _navigateToTab(1),
            onOpenGatewayConfig: _showBackendConfigSheet,
          ),
          WorkflowsTab(
            flows: _flows,
            onStartFlow: _startFlow,
            onRefresh: _loadCatalogAndDrafts,
            isLoading: _isLoadingCatalog,
          ),
          ActivityTab(
            activeDrafts: _activeDrafts,
            onResumeFlow: _resumeFlow,
            onDiscardDraft: _discardDraft,
          ),
          SettingsTab(
            activeDraftCount: _activeDrafts.length,
            onForceSync: _loadCatalogAndDrafts,
            onOpenGatewayConfig: _showBackendConfigSheet,
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(index: 0, icon: Icons.home_rounded, activeIcon: Icons.home_rounded, label: 'Home'),
              _navItem(index: 1, icon: Icons.grid_view_rounded, activeIcon: Icons.grid_view_rounded, label: 'Workflows'),
              _navItem(
                index: 2,
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long_rounded,
                label: 'Activity',
                badgeCount: _activeDrafts.isNotEmpty ? _activeDrafts.length : null,
              ),
              _navItem(index: 3, icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'Settings'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    int? badgeCount,
  }) {
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () => _navigateToTab(index),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  size: 22,
                  color: isSelected ? AppColors.primary : AppColors.textMuted,
                ),
                if (badgeCount != null)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
