class Memory {
  final String id;
  final String userId;
  final String title;
  final String content;
  final String category;
  final List<String> tags;
  final int importance;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Memory({
    required this.id,
    required this.userId,
    required this.title,
    required this.content,
    this.category = 'general',
    this.tags = const [],
    this.importance = 5,
    this.createdAt,
    this.updatedAt,
  });

  factory Memory.fromMap(Map<String, dynamic> map) {
    return Memory(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      category: map['category'] as String? ?? 'general',
      tags: (map['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      importance: map['importance'] as int? ?? 5,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'content': content,
      'category': category,
      'tags': tags,
      'importance': importance,
    };
  }
}
