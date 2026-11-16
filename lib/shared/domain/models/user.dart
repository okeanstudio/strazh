// lib/shared/domain/models/user.dart
class User {
  final String id;
  final String name;
  final String? bio;
  final String tag;
  final String? avatarUrl;
  final String? email;
  final bool emailVerified;
  final String? phone;
  final String? role;
  final String? status;
  final DateTime? birthDate;
  final String? inviteCode;
  final String? invitedByUserId;
  final String? identityPublicKey;
  final String? badge;

  const User({
    required this.id,
    required this.name,
    required this.tag,
    this.bio,
    this.avatarUrl,
    this.email,
    this.emailVerified = false,
    this.phone,
    this.role,
    this.status,
    this.birthDate,
    this.inviteCode,
    this.invitedByUserId,
    this.identityPublicKey,
    this.badge,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'],
      tag: json['tag'],
      bio: json['bio'],
      avatarUrl: json['avatar_url'],
      email: json['email'],
      emailVerified: json['email_verified'] ?? false,
      phone: json['phone'],
      role: json['role'],
      status: json['status'],
      birthDate: json['birth_date'] != null
          ? DateTime.tryParse(json['birth_date'])
          : null,
      inviteCode: json['invite_code'],
      invitedByUserId: json['invited_by_user_id'],
      identityPublicKey: json['identity_public_key'],
      badge: json['badge'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'tag': tag,
      'bio': bio,
      'avatar_url': avatarUrl,
      'email': email,
      'email_verified': emailVerified,
      'phone': phone,
      'role': role,
      'status': status,
      'birth_date': birthDate?.toIso8601String(),
      'invite_code': inviteCode,
      'invited_by_user_id': invitedByUserId,
      'identity_public_key': identityPublicKey,
      'badge': badge,
    };
  }
}