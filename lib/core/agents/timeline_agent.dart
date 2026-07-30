import 'agent_definition.dart';

/// ============================================
/// Timeline Agent (重构版)
/// ============================================
/// 职责：直接从用户消息生成时间线事件卡片
/// 一次 AI 调用完成，不再依赖 Fact 提取
/// ============================================

class TimelineAgent {
  static const AgentDefinition definition = AgentDefinition(
    id: 'timeline',
    name: 'Timeline Agent',
    description: '从用户消息直接生成时间线事件',
    model: 'deepseek-chat',
    temperature: 0.3,
    maxTokens: 800,
    systemPrompt: _systemPrompt,
    outputFormat: _outputFormat,
  );

  static const String _systemPrompt = '''
你是一个时间线记录员，把用户的消息变成一条时间线事件。

## 输出 JSON 格式
{
  "title": "一句话标题，不超过30字，像日记标题",
  "summary": "2-3句话摘要，补充细节和感受",
  "occurred_at": "ISO 8601时间",
  "time_precision": "day|week|month|year|unknown",
  "icon": "emoji图标"
}

## 规则
1. 用用户的语言风格，口语化
2. 只记录"发生了什么"，不评判好坏
3. 如果消息提到具体时间，用那个时间；否则用消息发送时间
4. 不要用 00:00:00，除非用户明确说凌晨零点
5. 如果消息是日常闲聊（如"你好""嗯""好的"），也要生成一条简短记录
6. icon 选一个最贴切的 emoji
7. 只输出 JSON，不要任何其他文字

## time_precision 判断
- 用户说"今天/昨天/7月21日" → day
- 用户说"上周/这周" → week
- 用户说"上个月/今年3月" → month
- 用户说"去年/2023年" → year
- 用户说"小时候/以前" → unknown
- 无法判断时间 → day（用消息发送时间）
''';

  static const String _outputFormat = '''
{
  "type": "object",
  "properties": {
    "title": { "type": "string", "description": "事件标题，不超过30字" },
    "summary": { "type": "string", "description": "事件摘要，2-3句话" },
    "occurred_at": { "type": "string", "format": "date-time" },
    "time_precision": { "type": "string", "enum": ["day", "week", "month", "year", "unknown"] },
    "icon": { "type": "string", "description": "emoji图标" }
  },
  "required": ["title", "summary", "occurred_at", "time_precision", "icon"]
}
''';

  /// 直接从用户消息构建 prompt（不再需要 factGroup + facts）
  static String buildUserPrompt({
    required String originalMessage,
    required DateTime messageCreatedAt,
  }) {
    return '''
请将以下用户消息转换为一条时间线事件卡片。

## 用户消息
"""
$originalMessage
"""

## 消息发送时间
${messageCreatedAt.toIso8601String()}

## 要求
1. 从消息中提取事件，生成标题和摘要
2. 如果消息提到具体时间，用那个时间；否则用消息发送时间
3. 只输出 JSON
''';
  }
}
