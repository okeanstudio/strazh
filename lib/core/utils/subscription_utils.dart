bool isPremiumSubscriptionActive(Map<String, dynamic>? metadata) {
  final subscriptionType = metadata?['subscription_type']
      ?.toString()
      .trim()
      .toLowerCase();
  final planId = metadata?['subscription_plan_id']
      ?.toString()
      .trim()
      .toLowerCase();

  if (subscriptionType != 'premium' && planId != 'forever') return false;

  final expiresAt = metadata?['subscription_expires_at']?.toString().trim();
  if (expiresAt?.toLowerCase() == 'forever' || planId == 'forever') {
    return true;
  }
  if (expiresAt == null || expiresAt.isEmpty) return false;

  final expiry = DateTime.tryParse(expiresAt);
  return expiry != null && expiry.isAfter(DateTime.now());
}
