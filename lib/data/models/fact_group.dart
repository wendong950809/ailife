class FactGroup {
  final String? id;
  final String messageId;
  final String userId;
  final String summary;
  final int factCount;
  final String? rawContent;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  FactGroup({
    this.id,
    required this.messageId,
    required this.userId,
    this.summary = '',
    this.factCount = 0,
    this.rawContent,
    this.createdAt,
    this.updatedAt,
  });

  factory FactGroup.fromMap(Map<String, dynamic> map) {
    return FactGroup(
      id: map['id'] as String?,
      messageId: map['message_id'] as String,
      userId: map['user_id'] as String,
      summary: map['summary'] as String? ?? '',
      factCount: map['fact_count'] as int? ?? 0,
      rawContent: map['raw_content'] as String?,
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
      'message_id': messageId,
      'user_id': userId,
      'summary': summary,
      'fact_count': factCount,
      'raw_content': rawContent,
    };
  }

  FactGroup copyWith({
    String? id,
    String? messageId,
    String? userId,
    String? summary,
    int? factCount,
    String? rawContent,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FactGroup(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      userId: userId ?? this.userId,
      summary: summary ?? this.summary,
      factCount: factCount ?? this.factCount,
      rawContent: rawContent ?? this.rawContent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
