class DailyLog {
  final String id;
  final String userId;
  final DateTime logDate;
  final int mood;
  final String? weather;
  final List<String> highlights;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DailyLog({
    required this.id,
    required this.userId,
    required this.logDate,
    this.mood = 3,
    this.weather,
    this.highlights = const [],
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory DailyLog.fromMap(Map<String, dynamic> map) {
    return DailyLog(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      logDate: DateTime.parse(map['log_date'] as String),
      mood: map['mood'] as int? ?? 3,
      weather: map['weather'] as String?,
      highlights: (map['highlights'] as List<dynamic>?)?.cast<String>() ?? [],
      notes: map['notes'] as String?,
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
      'log_date': logDate.toIso8601String().split('T').first,
      'mood': mood,
      'weather': weather,
      'highlights': highlights,
      'notes': notes,
    };
  }
}
