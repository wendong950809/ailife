/// ============================================
/// Agent 定义基类
/// ============================================
/// 所有 Agent 都继承此类，便于统一管理和扩展
/// 你可以在这个目录下新建更多 Agent 配置类
///
/// 配置项说明：
/// - name: Agent 名称
/// - description: Agent 功能描述
/// - model: 调用的大模型标识（如 'deepseek-chat', 'gpt-4o-mini'）
/// - systemPrompt: 系统提示词，定义 Agent 的行为规则
/// - temperature: 创造力参数（0-2）
/// - maxTokens: 最大输出 token 数
/// - outputFormat: 期望的输出格式描述（JSON Schema 或说明）
/// ============================================

class AgentDefinition {
  final String id;
  final String name;
  final String description;
  final String model;
  final String systemPrompt;
  final double temperature;
  final int maxTokens;
  final String outputFormat;
  final Map<String, dynamic>? extraParams;

  const AgentDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.model,
    required this.systemPrompt,
    this.temperature = 0.3,
    this.maxTokens = 2000,
    required this.outputFormat,
    this.extraParams,
  });

  @override
  String toString() {
    return 'AgentDefinition($id: $name, model=$model)';
  }
}

/// Agent 执行结果
class AgentResult<T> {
  final bool success;
  final T? data;
  final String? error;
  final int? tokensUsed;
  final DateTime executedAt;

  AgentResult({
    required this.success,
    this.data,
    this.error,
    this.tokensUsed,
  }) : executedAt = DateTime.now();

  factory AgentResult.success(T data, {int? tokensUsed}) {
    return AgentResult(
      success: true,
      data: data,
      tokensUsed: tokensUsed,
    );
  }

  factory AgentResult.failure(String error) {
    return AgentResult(
      success: false,
      error: error,
    );
  }
}
