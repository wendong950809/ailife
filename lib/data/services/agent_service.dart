import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient, Supabase, CountOption;
import '../../core/agents/agent_definition.dart';
import '../../core/agents/fact_extraction_agent.dart';
import '../../core/agents/timeline_agent.dart';
import '../models/extracted_fact.dart';
import '../models/fact_group.dart';
import '../models/timeline_event.dart';
import 'ai_service.dart';
import 'logging_service.dart';

/// ============================================
/// Agent 执行服务
/// ============================================
/// 统一管理和执行各种 Agent
/// 第一层: Fact Extraction → Message → Fact Group → Facts
/// ============================================

class ExtractResult {
  final FactGroup group;
  final List<ExtractedFact> facts;
  ExtractResult(this.group, this.facts);
}

class AgentService {
  final AiService _aiService;
  final SupabaseClient _supabase;
  final LoggingService? _loggingService;

  AgentService({
    required AiService aiService,
    SupabaseClient? supabase,
    LoggingService? loggingService,
  })  : _aiService = aiService,
        _supabase = supabase ?? Supabase.instance.client,
        _loggingService = loggingService;

  /// ============================================
  /// 执行事实提取 Agent（第一层）
  /// ============================================
  /// 流程:
  /// 1. 调用 AI 分析用户消息
  /// 2. 解析 JSON 结果 (summary + facts)
  /// 3. 删除该消息旧的 facts 和 fact_group
  /// 4. 创建 fact_group
  /// 5. 写入 extracted_facts（关联 fact_group_id）
  /// 6. 更新 messages 表的 extracted 标识
  /// ============================================
  Future<AgentResult<ExtractResult>> extractFacts({
    required String messageId,
    required String userId,
    required String userContent,
  }) async {
    final startTime = DateTime.now();
    try {
      debugPrint('🤖 [Agent] 开始提取事实, messageId=$messageId');

      final agent = FactExtractionAgent.definition;
      final messages = [
        {'role': 'system', 'content': agent.systemPrompt},
        {'role': 'user', 'content': FactExtractionAgent.buildUserPrompt(userContent)},
      ];

      final originalModel = _aiService.currentModel;
      _setAgentModel(agent.model);

      final response = await _aiService.chatCompletion(
        messages: messages,
        onStream: null,
        callType: 'fact_extraction',
        temperature: 0.2,
        onError: (error) {
          debugPrint('🤖 [Agent] AI 调用失败: $error');
        },
      );

      _aiService.setModel(originalModel);

      final parsed = _parseGroupResponse(response, messageId, userId);
      if (parsed == null) {
        await _markExtractionError(messageId, 'JSON 解析失败: $response');
        await _loggingService?.log(
          userId: userId,
          operationType: OperationType.fact_extract_failure,
          targetTable: 'extracted_facts',
          targetId: messageId,
          status: OperationStatus.failed,
          message: 'JSON 解析失败',
          requestData: {'user_content': userContent},
          errorDetails: 'JSON 解析失败: $response',
          durationMs: DateTime.now().difference(startTime).inMilliseconds,
        );
        return AgentResult.failure('JSON 解析失败');
      }

      final factGroup = parsed.group;
      final facts = parsed.facts;

      if (facts.isEmpty) {
        await _clearOldFacts(messageId);
        await _markExtracted(messageId);
        debugPrint('🤖 [Agent] 未提取到事实');
        await _loggingService?.log(
          userId: userId,
          operationType: OperationType.fact_extract_success,
          targetTable: 'extracted_facts',
          targetId: messageId,
          status: OperationStatus.success,
          message: '未提取到事实',
          requestData: {'user_content': userContent},
          responseData: {'fact_count': 0},
          durationMs: DateTime.now().difference(startTime).inMilliseconds,
        );
        return AgentResult.success(ExtractResult(factGroup, []));
      }

      final result = await _saveGroupWithFacts(factGroup, facts, messageId);

      await _markExtracted(messageId);

      debugPrint('🤖 [Agent] 提取完成, group=${factGroup.summary}, 共 ${facts.length} 条事实');
      for (final fact in facts) {
        debugPrint('   - ${fact.factType}.${fact.factKey} = ${fact.factValue} (conf=${fact.confidence})');
      }

      await _loggingService?.log(
        userId: userId,
        operationType: OperationType.fact_extract_success,
        targetTable: 'fact_groups',
        targetId: result.group.id ?? messageId,
        status: OperationStatus.success,
        message: '成功提取 ${facts.length} 条事实, 摘要: ${factGroup.summary}',
        requestData: {'user_content': userContent},
        responseData: {
          'group_summary': factGroup.summary,
          'fact_count': facts.length,
          'facts': facts.map((f) => f.toMap()).toList(),
        },
        durationMs: DateTime.now().difference(startTime).inMilliseconds,
      );

      return AgentResult.success(result);
    } catch (e, stackTrace) {
      debugPrint('🤖 [Agent] 提取异常: $e');
      debugPrint('🤖 [Agent] 堆栈: $stackTrace');
      await _markExtractionError(messageId, e.toString());
      await _loggingService?.log(
        userId: userId,
        operationType: OperationType.fact_extract_failure,
        targetTable: 'extracted_facts',
        targetId: messageId,
        status: OperationStatus.failed,
        message: '提取异常',
        requestData: {'user_content': userContent},
        errorDetails: '${e.toString()}\n$stackTrace',
        durationMs: DateTime.now().difference(startTime).inMilliseconds,
      );
      return AgentResult.failure(e.toString());
    }
  }

  /// ============================================
  /// 执行 Timeline Agent（第二层）
  /// ============================================
  /// 输入：Fact Group + Facts + 原始消息
  /// 输出：Timeline Event（存入 timeline 表）
  /// ============================================
  Future<AgentResult<TimelineEvent>> generateTimelineEvent({
    required String messageId,
    required String userId,
    required String originalMessage,
    required FactGroup factGroup,
    required List<ExtractedFact> facts,
    required DateTime messageCreatedAt,
    EventSource source = EventSource.chat,
  }) async {
    final startTime = DateTime.now();
    try {
      debugPrint('📅 [Agent] 开始生成 Timeline 事件, messageId=$messageId');

      if (facts.isEmpty) {
        debugPrint('📅 [Agent] 无事实，跳过 Timeline 生成');
        return AgentResult.failure('无事实可生成时间线');
      }

      final agent = TimelineAgent.definition;
      final messages = [
        {'role': 'system', 'content': agent.systemPrompt},
        {
          'role': 'user',
          'content': TimelineAgent.buildUserPrompt(
            originalMessage: originalMessage,
            factGroup: factGroup,
            facts: facts,
            messageCreatedAt: messageCreatedAt,
          ),
        },
      ];

      final originalModel = _aiService.currentModel;
      _setAgentModel(agent.model);

      final response = await _aiService.chatCompletion(
        messages: messages,
        onStream: null,
        callType: 'timeline_generation',
        temperature: agent.temperature,
        onError: (error) {
          debugPrint('📅 [Agent] AI 调用失败: $error');
        },
      );

      _aiService.setModel(originalModel);

      final event = _parseTimelineResponse(
        response,
        userId: userId,
        messageId: messageId,
        factGroupId: factGroup.id,
        source: source,
      );

      if (event == null) {
        debugPrint('📅 [Agent] Timeline JSON 解析失败');
        return AgentResult.failure('Timeline 解析失败');
      }

      final savedEvent = await _saveTimelineEvent(event);

      debugPrint('📅 [Agent] Timeline 事件生成完成: ${savedEvent.title}');

      await _loggingService?.log(
        userId: userId,
        operationType: OperationType.timeline_generate,
        targetTable: 'timeline',
        targetId: savedEvent.id ?? messageId,
        status: OperationStatus.success,
        message: '成功生成 Timeline 事件: ${savedEvent.title}',
        requestData: {
          'message_id': messageId,
          'fact_count': facts.length,
        },
        responseData: {
          'title': savedEvent.title,
          'icon': savedEvent.icon,
          'time_precision': savedEvent.timePrecision.name,
        },
        durationMs: DateTime.now().difference(startTime).inMilliseconds,
      );

      return AgentResult.success(savedEvent);
    } catch (e, stackTrace) {
      debugPrint('📅 [Agent] Timeline 生成异常: $e');
      debugPrint('📅 [Agent] 堆栈: $stackTrace');
      await _loggingService?.log(
        userId: userId,
        operationType: OperationType.timeline_generate,
        targetTable: 'timeline',
        targetId: messageId,
        status: OperationStatus.failed,
        message: 'Timeline 生成失败',
        requestData: {'message_id': messageId},
        errorDetails: '${e.toString()}\n$stackTrace',
        durationMs: DateTime.now().difference(startTime).inMilliseconds,
      );
      return AgentResult.failure(e.toString());
    }
  }

  /// 解析 Timeline Agent 返回的 JSON
  TimelineEvent? _parseTimelineResponse(
    String response, {
    required String userId,
    required String messageId,
    String? factGroupId,
    EventSource source = EventSource.chat,
  }) {
    try {
      String jsonStr = response.trim();
      if (jsonStr.startsWith('```json')) jsonStr = jsonStr.substring(7);
      if (jsonStr.startsWith('```')) jsonStr = jsonStr.substring(3);
      if (jsonStr.endsWith('```')) jsonStr = jsonStr.substring(0, jsonStr.length - 3);
      jsonStr = jsonStr.trim();

      final jsonObj = jsonDecode(jsonStr) as Map<String, dynamic>;

      final title = (jsonObj['title'] as String?)?.trim() ?? '';
      final summary = (jsonObj['summary'] as String?)?.trim() ?? '';
      final occurredAtStr = jsonObj['occurred_at'] as String?;
      final timePrecisionStr = jsonObj['time_precision'] as String? ?? 'unknown';
      final icon = jsonObj['icon'] as String?;

      if (title.isEmpty) return null;

      DateTime? occurredAt;
      if (occurredAtStr != null && occurredAtStr.isNotEmpty) {
        try {
          occurredAt = DateTime.parse(occurredAtStr);
        } catch (_) {
          occurredAt = null;
        }
      }

      return TimelineEvent(
        userId: userId,
        messageId: messageId,
        factGroupId: factGroupId,
        title: title,
        summary: summary,
        occurredAt: occurredAt,
        timePrecision: TimePrecision.fromString(timePrecisionStr),
        icon: icon,
        eventSource: source,
        rawContent: jsonStr,
      );
    } catch (e) {
      debugPrint('📅 [Agent] Timeline JSON 解析失败: $e');
      debugPrint('📅 [Agent] 原始响应: $response');
      return null;
    }
  }

  /// 保存 Timeline 事件到数据库
  Future<TimelineEvent> _saveTimelineEvent(TimelineEvent event) async {
    final data = await _supabase
        .from('timeline')
        .insert(event.toMap())
        .select()
        .single();

    final saved = TimelineEvent.fromMap(data as Map<String, dynamic>);
    debugPrint('✅ [Agent] Timeline 事件已保存: ${saved.id}');
    return saved;
  }

  void _setAgentModel(String modelId) {
    try {
      final model = AiModel.values.firstWhere((m) => m.id == modelId);
      _aiService.setModel(model);
    } catch (_) {
      debugPrint('🤖 [Agent] 模型 $modelId 未找到，使用当前模型');
    }
  }

  /// 解析 AI 返回的 JSON 对象 (summary + facts)
  FactGroupAndFacts? _parseGroupResponse(
    String response,
    String messageId,
    String userId,
  ) {
    try {
      String jsonStr = response.trim();
      if (jsonStr.startsWith('```json')) jsonStr = jsonStr.substring(7);
      if (jsonStr.startsWith('```')) jsonStr = jsonStr.substring(3);
      if (jsonStr.endsWith('```')) jsonStr = jsonStr.substring(0, jsonStr.length - 3);
      jsonStr = jsonStr.trim();

      final jsonObj = jsonDecode(jsonStr) as Map<String, dynamic>;
      final summary = (jsonObj['summary'] as String?)?.trim() ?? '';
      final factsJson = jsonObj['facts'] as List<dynamic>? ?? [];

      final facts = <ExtractedFact>[];
      for (final item in factsJson) {
        final map = item as Map<String, dynamic>;
        facts.add(ExtractedFact(
          messageId: messageId,
          userId: userId,
          factType: map['fact_type'] as String? ?? 'other',
          factKey: map['fact_key'] as String? ?? 'content',
          factValue: map['fact_value']?.toString() ?? '',
          confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
          rawContent: jsonStr,
        ));
      }

      final group = FactGroup(
        messageId: messageId,
        userId: userId,
        summary: summary,
        factCount: facts.length,
        rawContent: jsonStr,
      );

      return FactGroupAndFacts(group, facts);
    } catch (e) {
      debugPrint('🤖 [Agent] JSON 解析失败: $e');
      debugPrint('🤖 [Agent] 原始响应: $response');
      return null;
    }
  }

  /// 删除该消息旧的 facts 和 fact_group
  Future<void> _clearOldFacts(String messageId) async {
    try {
      final oldGroups = await _supabase
          .from('fact_groups')
          .select('id')
          .eq('message_id', messageId);
      final groupIds = (oldGroups as List)
          .map((g) => (g as Map<String, dynamic>)['id'] as String)
          .toList();

      await _supabase.from('extracted_facts').delete().eq('message_id', messageId);
      if (groupIds.isNotEmpty) {
        await _supabase.from('fact_groups').delete().eq('message_id', messageId);
      }
      debugPrint('🗑️ [Agent] 已清理旧数据: ${groupIds.length} 个 group');
    } catch (e) {
      debugPrint('⚠️ [Agent] 清理旧数据失败: $e');
    }
  }

  /// 保存 fact_group 和 facts（事务性操作）
  Future<ExtractResult> _saveGroupWithFacts(
    FactGroup group,
    List<ExtractedFact> facts,
    String messageId,
  ) async {
    await _clearOldFacts(messageId);

    final groupData = await _supabase
        .from('fact_groups')
        .insert(group.toMap())
        .select()
        .single();

    final savedGroup = FactGroup.fromMap(groupData as Map<String, dynamic>);
    final groupId = savedGroup.id!;

    final factsWithGroup = facts
        .map((f) => f.copyWith(factGroupId: groupId).toMap())
        .toList();

    await _supabase.from('extracted_facts').insert(factsWithGroup);

    final verify = await _supabase
        .from('extracted_facts')
        .select('id')
        .eq('fact_group_id', groupId);
    final savedCount = (verify as List).length;

    if (savedCount != facts.length) {
      throw Exception('事实保存不完整: 期望 ${facts.length} 条，实际保存 $savedCount 条');
    }

    debugPrint('✅ [Agent] 成功保存 group=${savedGroup.summary}, ${facts.length} 条事实');
    return ExtractResult(savedGroup, facts);
  }

  Future<void> _markExtracted(String messageId) async {
    try {
      await _supabase.from('messages').update({
        'extracted': true,
        'extraction_error': null,
      }).eq('id', messageId);

      final result = await _supabase
          .from('messages')
          .select('extracted')
          .eq('id', messageId)
          .single();

      if (result['extracted'] != true) {
        throw Exception('消息标记已提取失败: extracted 字段未更新为 true');
      }
      debugPrint('✅ [Agent] 消息 $messageId 已成功标记为已提取');
    } catch (e) {
      debugPrint('❌ [Agent] 标记消息已提取失败: $e');
      rethrow;
    }
  }

  Future<void> _markExtractionError(String messageId, String error) async {
    try {
      await _supabase.from('messages').update({
        'extracted': false,
        'extraction_error': error,
      }).eq('id', messageId);

      final result = await _supabase
          .from('messages')
          .select('extracted, extraction_error')
          .eq('id', messageId)
          .single();

      if (result['extracted'] != false || result['extraction_error'] != error) {
        throw Exception('消息标记提取失败失败: 字段未正确更新');
      }
      debugPrint('✅ [Agent] 消息 $messageId 已成功标记为提取失败');
    } catch (e) {
      debugPrint('❌ [Agent] 标记消息提取失败失败: $e');
      rethrow;
    }
  }

  Future<void> batchExtractUnprocessed({int limit = 50}) async {
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .eq('role', 'user')
          .eq('extracted', false)
          .isFilter('extraction_error', null)
          .order('created_at', ascending: true)
          .limit(limit);

      if (response is! List || response.isEmpty) return;

      debugPrint('🤖 [Agent] 批量提取: ${response.length} 条消息');

      for (final msg in response) {
        final messageId = msg['id'] as String?;
        final userId = msg['user_id'] as String?;
        final content = msg['content'] as String?;

        if (messageId != null && userId != null && content != null) {
          await extractFacts(
            messageId: messageId,
            userId: userId,
            userContent: content,
          );
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      debugPrint('🤖 [Agent] 批量提取失败: $e');
    }
  }

  void debugPrint(String message) {
    print(message);
  }
}

class FactGroupAndFacts {
  final FactGroup group;
  final List<ExtractedFact> facts;
  FactGroupAndFacts(this.group, this.facts);
}
