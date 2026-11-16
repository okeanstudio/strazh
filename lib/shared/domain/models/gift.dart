class Gift {
  const Gift({
    required this.id,
    required this.name,
    required this.emoji,
    required this.priceEnc,
    this.animationUrl,
  });

  final String id;
  final String name;
  final String emoji;
  final int priceEnc;
  final String? animationUrl;

  factory Gift.fromJson(Map<String, dynamic> json) {
    return Gift(
      id: json['id'] as String,
      name: json['name'] as String,
      emoji: json['emoji'] as String,
      priceEnc: (json['price_enc'] as num).toInt(),
      animationUrl: json['animation_url'] as String?,
    );
  }
}
