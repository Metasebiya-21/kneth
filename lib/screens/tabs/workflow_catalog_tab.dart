import 'package:flutter/material.dart';

import '../../models/flow_manifest.dart';

class WorkflowCatalogTab extends StatefulWidget {
  final List<FlowManifest> flows;
  final Function(FlowManifest) onStartFlow;
  final VoidCallback onRefresh;
  final bool isLoading;

  const WorkflowCatalogTab({
    super.key,
    required this.flows,
    required this.onStartFlow,
    required this.onRefresh,
    this.isLoading = false,
  });

  @override
  State<WorkflowCatalogTab> createState() => _WorkflowCatalogTabState();
}

class _WorkflowCatalogTabState extends State<WorkflowCatalogTab> {
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

    return RefreshIndicator(
      color: const Color(0xFF34D399),
      onRefresh: () async => widget.onRefresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
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
                    'Workflow Catalog',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFE2E8F0),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${filteredFlows.length} server-driven schema${filteredFlows.length == 1 ? '' : 's'} available',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Sync Flows',
                icon: widget.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF34D399)),
                      )
                    : const Icon(Icons.sync_rounded, color: Color(0xFF94A3B8)),
                onPressed: widget.onRefresh,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search Bar
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF334155)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search workflows (KYC, KYB, Fayda, Loan)...',
                hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8)),
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
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Category Chips
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
                    selectedColor: const Color(0xFF34D399),
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFF06281B) : const Color(0xFFCBD5E1),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                    backgroundColor: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF34D399) : const Color(0xFF334155),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),

          // Workflow Cards
          if (filteredFlows.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
                  SizedBox(height: 12),
                  Text('No workflows found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFE2E8F0))),
                  SizedBox(height: 4),
                  Text('Try choosing another category or clearing your search.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                ],
              ),
            ),
          ] else ...[
            ...filteredFlows.map((flow) => _buildFlowCard(flow)),
          ],
        ],
      ),
    );
  }

  Widget _buildFlowCard(FlowManifest flow) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => widget.onStartFlow(flow),
        borderRadius: BorderRadius.circular(22),
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
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(_getCategoryIcon(flow.category), color: Colors.white, size: 24),
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
                            fontSize: 15.5,
                            color: Color(0xFFE2E8F0),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          flow.description,
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.35),
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
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFFE2E8F0)),
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
                      color: const Color(0xFF064E3B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF065F46)),
                    ),
                    child: Text(
                      flow.category.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF6EE7B7),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(
                          flow.estimatedDuration,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
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
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.layers_outlined, size: 12, color: Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Text(
                          '${flow.stageCount} Stages',
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
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
