class UserProfile {
  final String id;
  final String? username;
  final String? avatarUrl;
  final String? bio;
  final DateTime? birthday;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? aiName;
  final String? aiAvatarUrl;
  final String? nickname;

  UserProfile({
    required this.id,
    this.username,
    this.avatarUrl,
    this.bio,
    this.birthday,
    this.createdAt,
    this.updatedAt,
    this.aiName,
    this.aiAvatarUrl,
    this.nickname,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      username: map['username'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      bio: map['bio'] as String?,
      birthday: map['birthday'] != null
          ? DateTime.parse(map['birthday'] as String)
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      aiName: map['ai_name'] as String?,
      aiAvatarUrl: map['ai_avatar_url'] as String?,
      nickname: map['nickname'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'avatar_url': avatarUrl,
      'bio': bio,
      'birthday': birthday?.toIso8601String().split('T').first,
      'ai_name': aiName,
      'ai_avatar_url': aiAvatarUrl,
      'nickname': nickname,
    };
  }

  UserProfile copyWith({
    String? id,
    String? username,
    String? avatarUrl,
    String? bio,
    DateTime? birthday,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? aiName,
    String? aiAvatarUrl,
    String? nickname,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      birthday: birthday ?? this.birthday,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      aiName: aiName ?? this.aiName,
      aiAvatarUrl: aiAvatarUrl ?? this.aiAvatarUrl,
      nickname: nickname ?? this.nickname,
    );
  }
}
