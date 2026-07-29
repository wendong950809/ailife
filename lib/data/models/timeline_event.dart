enum TimePrecision {
  day,
  week,
  month,
  year,
  unknown;

  static TimePrecision fromString(String value) {
    return TimePrecision.values.firstWhere(
      (e) => e.name == value,
      orElse: () => TimePrecision.unknown,
    );
  }
}

enum EventSource {
  chat,
  photo,
  voice,
  calendar,
  document,
  health;

  static EventSource fromString(String value) {
    return EventSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => EventSource.chat,
    );
  }
}

class TimelineEvent {
  final String? id;
  final String userId;
  final String? messageId;
  final String? factGroupId;
  final String title;
  final String summary;
  final DateTime? occurredAt;
  final TimePrecision timePrecision;
  final String? icon;
  final EventSource eventSource;
  final String? rawContent;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  TimelineEvent({
    this.id,
    required this.userId,
    this.messageId,
    this.factGroupId,
    this.title = '',
    this.summary = '',
    this.occurredAt,
    this.timePrecision = TimePrecision.unknown,
    this.icon,
    this.eventSource = EventSource.chat,
    this.rawContent,
    this.createdAt,
    this.updatedAt,
  });

  factory TimelineEvent.fromMap(Map<String, dynamic> map) {
    return TimelineEvent(
      id: map['id'] as String?,
      userId: map['user_id'] as String,
      messageId: map['message_id'] as String?,
      factGroupId: map['fact_group_id'] as String?,
      title: map['title'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
      occurredAt: map['occurred_at'] != null
          ? DateTime.parse(map['occurred_at'] as String)
          : null,
      timePrecision: TimePrecision.fromString(
          map['time_precision'] as String? ?? 'unknown'),
      icon: map['icon'] as String?,
      eventSource:
          EventSource.fromString(map['event_source'] as String? ?? 'chat'),
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
      'user_id': userId,
      'message_id': messageId,
      'fact_group_id': factGroupId,
      'title': title,
      'summary': summary,
      'occurred_at': occurredAt?.toIso8601String(),
      'time_precision': timePrecision.name,
      'icon': icon,
      'event_source': eventSource.name,
      'raw_content': rawContent,
    };
  }

  TimelineEvent copyWith({
    String? id,
    String? userId,
    String? messageId,
    String? factGroupId,
    String? title,
    String? summary,
    DateTime? occurredAt,
    TimePrecision? timePrecision,
    String? icon,
    EventSource? eventSource,
    String? rawContent,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TimelineEvent(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      messageId: messageId ?? this.messageId,
      factGroupId: factGroupId ?? this.factGroupId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      occurredAt: occurredAt ?? this.occurredAt,
      timePrecision: timePrecision ?? this.timePrecision,
      icon: icon ?? this.icon,
      eventSource: eventSource ?? this.eventSource,
      rawContent: rawContent ?? this.rawContent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'TimelineEvent($title, ${timePrecision.name}, $icon)';
  }
}
