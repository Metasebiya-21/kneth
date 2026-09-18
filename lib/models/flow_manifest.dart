import 'package:flutter/material.dart';

/// Identifies which flow to run. Can be fetched dynamically from the server
/// via [ApiClient.fetchAvailableFlows] or loaded from local cache.
class FlowManifest {
  final String flowId;
  final String title;
  final String description;
  final IconData icon;
  final String category;
  final int estimatedMinutes;
  final Color badgeColor;
  final bool isFeatured;
  final String version;
  final int stageCount;

  const FlowManifest({
    required this.flowId,
    this.title = 'Data Collection',
    this.description = 'Standard registration workflow',
    this.icon = Icons.assignment_outlined,
    this.category = 'General',
    this.estimatedMinutes = 5,
    this.badgeColor = const Color(0xFF00897B),
    this.isFeatured = false,
    this.version = '1.0.0',
    this.stageCount = 4,
  });

  String get estimatedDuration => '~$estimatedMinutes min';

  factory FlowManifest.fromJson(Map<String, dynamic> json) {
    int parseNum(dynamic val, int defaultVal) {
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? defaultVal;
      return defaultVal;
    }

    return FlowManifest(
      flowId: json['flowId'] as String? ?? 'flow_default',
      title: json['title'] as String? ?? 'Workflow',
      description: json['description'] as String? ?? '',
      icon: _parseIcon(json['icon'] as String?),
      category: json['category'] as String? ?? 'General',
      estimatedMinutes: parseNum(json['estimatedMinutes'], 5),
      badgeColor: _parseColor(json['badgeColor'] as String?),
      isFeatured: json['isFeatured'] as bool? ?? false,
      version: json['version'] as String? ?? '1.0.0',
      stageCount: parseNum(json['stageCount'], 4),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'flowId': flowId,
      'title': title,
      'description': description,
      'icon': _iconToString(icon),
      'category': category,
      'estimatedMinutes': estimatedMinutes,
      'badgeColor': '#${badgeColor.toARGB32().toRadixString(16).padLeft(8, '0')}',
      'isFeatured': isFeatured,
      'version': version,
      'stageCount': stageCount,
    };
  }

  static IconData _parseIcon(String? raw) {
    switch (raw) {
      case 'badge':
      case 'kyc':
        return Icons.badge_outlined;
      case 'storefront':
      case 'kyb':
        return Icons.storefront_outlined;
      case 'agriculture':
      case 'farmer':
        return Icons.agriculture_outlined;
      case 'flash_on':
      case 'fast':
        return Icons.flash_on_outlined;
      case 'account_balance':
        return Icons.account_balance_outlined;
      case 'credit_card':
        return Icons.credit_card_outlined;
      default:
        return Icons.assignment_outlined;
    }
  }

  static String _iconToString(IconData icon) {
    if (icon == Icons.badge_outlined) return 'badge';
    if (icon == Icons.storefront_outlined) return 'storefront';
    if (icon == Icons.agriculture_outlined) return 'agriculture';
    if (icon == Icons.flash_on_outlined) return 'flash_on';
    if (icon == Icons.account_balance_outlined) return 'account_balance';
    return 'assignment';
  }

  static Color _parseColor(String? raw) {
    if (raw == null || raw.isEmpty) return const Color(0xFF00897B);
    try {
      final hex = raw.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return const Color(0xFF00897B);
  }

  static const List<FlowManifest> defaultCatalog = [
    FlowManifest(
      flowId: 'kyc_kyb_collection',
      title: 'Customer KYC (Fayda)',
      description: 'Individual onboarding with Fayda verification & ID capture',
      icon: Icons.badge_outlined,
      category: 'Individuals',
      estimatedMinutes: 4,
      badgeColor: Color(0xFF00897B),
      isFeatured: true,
      stageCount: 5,
    ),
    FlowManifest(
      flowId: 'merchant_kyb',
      title: 'Merchant KYB Onboarding',
      description: 'Business registration, TIN verification & trade license',
      icon: Icons.storefront_outlined,
      category: 'Enterprises',
      estimatedMinutes: 6,
      badgeColor: Color(0xFF1E88E5),
      isFeatured: true,
      stageCount: 4,
    ),
    FlowManifest(
      flowId: 'agri_loan_onboarding',
      title: 'Farmer & Agri-Credit KYC',
      description: 'Agricultural microfinance onboarding & crop data collection',
      icon: Icons.agriculture_outlined,
      category: 'Agri-Finance',
      estimatedMinutes: 5,
      badgeColor: Color(0xFF43A047),
      stageCount: 3,
    ),
    FlowManifest(
      flowId: 'fayda_fast_track',
      title: 'Fayda Fast-Track Verification',
      description: 'Instant FIN lookup & biometric photo capture',
      icon: Icons.flash_on_outlined,
      category: 'Verification',
      estimatedMinutes: 2,
      badgeColor: Color(0xFFFB8C00),
      stageCount: 2,
    ),
  ];
}