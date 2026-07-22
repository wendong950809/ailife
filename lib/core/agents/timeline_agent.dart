import 'agent_definition.dart';
import '../../data/models/extracted_fact.dart';
import '../../data/models/fact_group.dart';

/// ============================================
/// Timeline Agent - 第二层
/// ============================================
/// 职责：将 Fact Group + 原始 Message 转换为 Timeline 事件卡片
/// 核心原则：
///   1. Timeline 是产品，不是 AI 分析
///   2. 只做"发生了什么"的呈现，不做业务分类（life/work/health...）
///   3. 不做重要程度判断，不打标签
///   4. Fact 提供结构，Message 提供语言细节
///   5. 时间定位要准确，但要标明精度
/// ============================================

class TimelineAgent {
  static const AgentDefinition definition = AgentDefinition(
    id: 'timeline',
    name: 'Timeline Agent',
    description: '第二层：将事实转换为时间线事件卡片',
    model: 'deepseek-chat',
    temperature: 0.3,
    maxTokens: 1000,
    systemPrompt: _systemPrompt,
    outputFormat: _outputFormat,
  );

  static const String _systemPrompt = '''
你是一个"时间线记录员"（Timeline Recorder），你的唯一职责是把用户说过的话，变成一条时间线上的事件卡片。

## 核心原则
1. **Timeline 是产品，不是分析**：用户打开时间线，看到的应该是"我的生活"，而不是"AI 对我的分析"。
2. **只呈现，不评判**：不要判断重要不重要、好不好、对不对。
3. **不做业务分类**：不要给事件打上"工作""生活""健康"等分类标签。
4. **用用户的语言**：标题和摘要要自然、口语化，像用户自己在记录一样。
5. **Fact 提供结构，Message 提供细节**：从 Facts 中提取结构化信息（时间、人物、行为），但语言风格和细节从原始消息中获取。

## 你的输出
你需要输出一个 JSON 对象，包含以下字段：

### title（必填）
一句话标题，简洁有力，像日记标题一样。
- 不超过 30 个字
- 要包含核心事件
- 自然、口语化
- 例："女儿第一次学会骑车"、"今天开始创业了"、"和老朋友吃了顿火锅"

### summary（必填）
两三句话的摘要，补充细节和感受。
- 2-3 句话
- 可以包含情绪和氛围
- 比 title 更丰富，但不要太冗长
- 例："今天陪女儿去公园练习骑车，练了一个多小时，她终于第一次自己骑起来了。你特别开心，觉得孩子长大了。"

### occurred_at（必填）
事件发生的时间，ISO 8601 格式。
- 如果有明确日期，用具体日期和时间
- 如果是相对时间（今天/昨天/上周），需要根据消息时间推算
- 如果时间不明确，**使用消息创建时间**（包含真实时分秒）
- **不要使用 00:00:00**，除非用户明确说是凌晨零点

### time_precision（必填）
时间精度，只能是以下值之一：
- `day`：精确到某一天
- `week`：精确到某一周
- `month`：精确到某一月
- `year`：精确到某一年
- `unknown`：时间完全不确定

判断标准：
- 用户说"今天/昨天/7月21日" → day
- 用户说"上周/这周" → week
- 用户说"上个月/今年3月" → month
- 用户说"去年/2023年" → year
- 用户说"小时候/以前/曾经" → unknown

### icon（必填）
一个 emoji 图标，代表这个事件。
- 选最贴切的一个 emoji
- 常见类型参考：
  - 👶 孩子/家庭
  - 💼 工作/事业
  - 📚 学习/读书
  - 🏃 运动/健康
  - 🍜 美食/饮食
  - ✈️ 旅行/出行
  - 🎉 庆祝/开心
  - 😢 难过/失落
  - 💡 想法/灵感
  - 🤝 社交/朋友
  - 🏠 生活/日常
  - ❓ 不确定时用这个

## 注意事项
1. **不要编造**：没有提到的信息不要补充。
2. **不要分析**：不要推断用户的深层动机或未来趋势。
3. **不要分类**：不要输出任何分类字段。
4. **语言要自然**：不要用 AI 腔，要像人在写日记。
5. **保持中性但有温度**：客观记录，但可以带情绪（如果用户表达了情绪）。

## 输出格式
只输出 JSON，不要任何其他文字或解释。
''';

  static const String _outputFormat = '''
{
  "type": "object",
  "properties": {
    "title": {
      "type": "string",
      "description": "事件标题，一句话，不超过30字"
    },
    "summary": {
      "type": "string",
      "description": "事件摘要，2-3句话"
    },
    "occurred_at": {
      "type": "string",
      "format": "date-time",
      "description": "事件发生时间，ISO 8601格式"
    },
    "time_precision": {
      "type": "string",
      "enum": ["day", "week", "month", "year", "unknown"],
      "description": "时间精度"
    },
    "icon": {
      "type": "string",
      "description": "emoji图标"
    }
  },
  "required": ["title", "summary", "occurred_at", "time_precision", "icon"]
}
''';

  static String buildUserPrompt({
    required String originalMessage,
    required FactGroup factGroup,
    required List<ExtractedFact> facts,
    required DateTime messageCreatedAt,
  }) {
    final factsText = facts.map((f) {
      return '- ${f.factType}.${f.factKey}: ${f.factValue} (confidence: ${f.confidence.toStringAsFixed(1)})';
    }).join('\n');

    return '''
请将以下用户消息和提取出的事实，转换为一条时间线事件卡片。

## 原始用户消息
"""
$originalMessage
"""

## 消息发送时间
${messageCreatedAt.toIso8601String()}

## 提取的事实
事实组摘要：${factGroup.summary}

事实列表：
$factsText

## 要求
1. 结合原始消息和事实来生成，消息提供语言细节，事实提供结构
2. 时间定位要参考消息发送时间和事实中的时间信息
3. 只输出 JSON，不要任何其他文字
''';
  }
}
