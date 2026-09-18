import 'package:flutter/material.dart';

import '../../models/flow_manifest.dart';
import '../../theme/app_colors.dart';

class WorkflowsTab extends StatefulWidget {
  final List<FlowManifest> flows;
  final Function(FlowManifest) onStartFlow;
  final VoidCallback onRefresh;
  final bool isLoading;

  const WorkflowsTab({
    super.key,
    required this.flows,
    required this.onStartFlow,
    required this.onRefresh,
    this.isLoading = false,
  });

  @override
  State<WorkflowsTab> createState() => _WorkflowsTabState();
}

class _WorkflowsTabState extends State<WorkflowsTab> {
  String _selectedCategory = 'All';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final allFlows = widget.flows.isNotEmpty ? widget.flows : FlowManifest.defaultCatalog;
    final categories = ['All', ...allFlows.map((e) => e.category).toSet()];

    final filteredFlows = allFlows.where((flow) {
      final matchesCat = _selectedCategory == 'All' || flow.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          flow.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          flow.description.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCat && matchesSearch;
    }).toList();

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async => widget.onRefresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Workflows',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${filteredFlows.length} available',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Sync',
                  icon: widget.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      : const Icon(Icons.sync_rounded, color: AppColors.textMuted),
                  onPressed: widget.onRefresh,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(color: AppColors.shadowLight, blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search workflows...',
                  hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  fillColor: Colors.transparent,
                  filled: true,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Category Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                      selectedColor: AppColors.primaryLight,
                      checkmarkColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? AppColors.primary : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                      backgroundColor: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? AppColors.primary.withAlpha(80) : AppColors.border,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 18),

            // Workflow Cards
            if (filteredFlows.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                decoration: AppColors.cardDecoration,
                child: const Column(
                  children: [
                    Icon(Icons.search_off_rounded, size: 48, color: AppColors.textMuted),
                    SizedBox(height: 12),
                    Text('No workflows found', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                    SizedBox(height: 4),
                    Text('Try another category or clear search.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
              )
            else
              ...filteredFlows.map((flow) => _buildFlowCard(flow)),
          ],
        ),
      ),
    );
  }

  Widget _buildFlowCard(FlowManifest flow) {
    final gradientColors = _getCategoryGradient(flow.category);
    final accentColor = gradientColors[0];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: AppColors.shadowLight, blurRadius: 12, offset: Offset(0, 3)),
        ],
      ),
      child: InkWell(
        onTap: () => widget.onStartFlow(flow),
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            // Left accent bar
            Container(
              width: 4,
              height: 90,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: gradientColors),
                        borderRadius: BorderRadius.circular(12),
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
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            flow.description,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _metaChip(Icons.timer_outlined, flow.estimatedDuration),
                              const SizedBox(width: 6),
                              _metaChip(Icons.layers_outlined, '${flow.stageCount} Steps'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 22),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceDim,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.textMuted),
          const SizedBox(width: 3),
          Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  List<Color> _getCategoryGradient(String category) {
    switch (category.toLowerCase()) {
      case 'kyc': case 'personal': case 'individuals':
        return [AppColors.accentEmerald, const Color(0xFF34D399)];
      case 'kyb': case 'merchant': case 'enterprises':
        return [AppColors.accentSky, const Color(0xFF38BDF8)];
      case 'lending': case 'loans': case 'agri-finance':
        return [AppColors.accentViolet, const Color(0xFFA78BFA)];
      case 'verification': case 'identity':
        return [AppColors.accentAmber, const Color(0xFFFBBF24)];
      default:
        return [AppColors.primary, const Color(0xFF818CF8)];
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'kyc': case 'personal': case 'individuals':
        return Icons.badge_rounded;
      case 'kyb': case 'merchant': case 'enterprises':
        return Icons.store_rounded;
      case 'lending': case 'loans': case 'agri-finance':
        return Icons.agriculture_rounded;
      case 'verification': case 'identity':
        return Icons.fingerprint_rounded;
      default:
        return Icons.dynamic_form_rounded;
    }
  }
}
