/// ============================================
/// 结构化事实数据模型
/// ============================================
/// 对应 extracted_facts 表

class ExtractedFact {
  final String? id;
  final String messageId;
  final String userId;
  final String? factGroupId;
  final String factType;
  final String factKey;
  final String factValue;
  final double confidence;
  final String? rawContent;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ExtractedFact({
    this.id,
    required this.messageId,
    required this.userId,
    this.factGroupId,
    required this.factType,
    required this.factKey,
    required this.factValue,
    this.confidence = 0.0,
    this.rawContent,
    this.createdAt,
    this.updatedAt,
  });

  factory ExtractedFact.fromMap(Map<String, dynamic> map) {
    return ExtractedFact(
      id: map['id'] as String?,
      messageId: map['message_id'] as String,
      userId: map['user_id'] as String,
      factGroupId: map['fact_group_id'] as String?,
      factType: map['fact_type'] as String,
      factKey: map['fact_key'] as String,
      factValue: map['fact_value'] as String,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
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
      'fact_group_id': factGroupId,
      'fact_type': factType,
      'fact_key': factKey,
      'fact_value': factValue,
      'confidence': confidence,
      'raw_content': rawContent,
    };
  }

  ExtractedFact copyWith({
    String? id,
    String? messageId,
    String? userId,
    String? factGroupId,
    String? factType,
    String? factKey,
    String? factValue,
    double? confidence,
    String? rawContent,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExtractedFact(
      id: id ?? this.id,
      messageId: messageId ?? this.messageId,
      userId: userId ?? this.userId,
      factGroupId: factGroupId ?? this.factGroupId,
      factType: factType ?? this.factType,
      factKey: factKey ?? this.factKey,
      factValue: factValue ?? this.factValue,
      confidence: confidence ?? this.confidence,
      rawContent: rawContent ?? this.rawContent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'ExtractedFact($factType.$factKey=$factValue, conf=$confidence)';
  }
}
