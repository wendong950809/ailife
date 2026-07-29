import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

enum OperationType {
  message_send,
  message_save,
  message_load,
  ai_response,
  ai_error,
  fact_extract,
  fact_extract_success,
  fact_extract_failure,
  timeline_generate,
  auth_login,
  auth_login_success,
  auth_login_failure,
  auth_register,
  auth_register_success,
  auth_register_failure,
  auth_logout,
  profile_update,
  profile_update_success,
  profile_update_failure,
  memory_create,
  memory_update,
  memory_delete,
  daily_log_create,
  daily_log_update,
  system_startup,
  system_error,
  database_query,
  database_insert,
  database_update,
  database_delete,
  http_request,
  http_response,
  http_error,
  unknown,
}

enum OperationStatus { success, failed, pending, info }

extension OperationTypeExtension on OperationType {
  String get displayName {
    switch (this) {
      case OperationType.message_send: return '发送消息';
      case OperationType.message_save: return '保存消息';
      case OperationType.message_load: return '加载消息';
      case OperationType.ai_response: return 'AI响应';
      case OperationType.ai_error: return 'AI错误';
      case OperationType.fact_extract: return '事实提取';
      case OperationType.fact_extract_success: return '提取成功';
      case OperationType.fact_extract_failure: return '提取失败';
      case OperationType.timeline_generate: return '生成时间线';
      case OperationType.auth_login: return '登录';
      case OperationType.auth_login_success: return '登录成功';
      case OperationType.auth_login_failure: return '登录失败';
      case OperationType.auth_register: return '注册';
      case OperationType.auth_register_success: return '注册成功';
      case OperationType.auth_register_failure: return '注册失败';
      case OperationType.auth_logout: return '登出';
      case OperationType.profile_update: return '更新资料';
      case OperationType.profile_update_success: return '更新成功';
      case OperationType.profile_update_failure: return '更新失败';
      case OperationType.memory_create: return '创建记忆';
      case OperationType.memory_update: return '更新记忆';
      case OperationType.memory_delete: return '删除记忆';
      case OperationType.daily_log_create: return '创建日志';
      case OperationType.daily_log_update: return '更新日志';
      case OperationType.system_startup: return '系统启动';
      case OperationType.system_error: return '系统错误';
      case OperationType.database_query: return '数据库查询';
      case OperationType.database_insert: return '数据库插入';
      case OperationType.database_update: return '数据库更新';
      case OperationType.database_delete: return '数据库删除';
      case OperationType.http_request: return 'HTTP请求';
      case OperationType.http_response: return 'HTTP响应';
      case OperationType.http_error: return 'HTTP错误';
      default: return '未知操作';
    }
  }

  String get category {
    switch (this) {
      case OperationType.message_send:
      case OperationType.message_save:
      case OperationType.message_load:
        return '消息';
      case OperationType.ai_response:
      case OperationType.ai_error:
        return 'AI';
      case OperationType.fact_extract:
      case OperationType.fact_extract_success:
      case OperationType.fact_extract_failure:
        return '事实提取';
      case OperationType.timeline_generate:
        return '时间线';
      case OperationType.auth_login:
      case OperationType.auth_login_success:
      case OperationType.auth_login_failure:
      case OperationType.auth_register:
      case OperationType.auth_register_success:
      case OperationType.auth_register_failure:
      case OperationType.auth_logout:
        return '认证';
      case OperationType.profile_update:
      case OperationType.profile_update_success:
      case OperationType.profile_update_failure:
        return '用户';
      case OperationType.memory_create:
      case OperationType.memory_update:
      case OperationType.memory_delete:
      case OperationType.daily_log_create:
      case OperationType.daily_log_update:
        return '业务';
      case OperationType.system_startup:
      case OperationType.system_error:
        return '系统';
      case OperationType.database_query:
      case OperationType.database_insert:
      case OperationType.database_update:
      case OperationType.database_delete:
        return '数据库';
      case OperationType.http_request:
      case OperationType.http_response:
      case OperationType.http_error:
        return '网络';
      default:
        return '其他';
    }
  }
}

class OperationLog {
  final String id;
  final String userId;
  final OperationType operationType;
  final String targetTable;
  final String? targetId;
  final OperationStatus status;
  final String? message;
  final Map<String, dynamic>? requestData;
  final Map<String, dynamic>? responseData;
  final String? errorDetails;
  final int? durationMs;
  final DateTime createdAt;

  OperationLog({
    required this.id,
    required this.userId,
    required this.operationType,
    required this.targetTable,
    this.targetId,
    required this.status,
    this.message,
    this.requestData,
    this.responseData,
    this.errorDetails,
    this.durationMs,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'operation_type': operationType.name,
      'target_table': targetTable,
      'target_id': targetId,
      'status': status.name,
      'message': message,
      'request_data': requestData,
      'response_data': responseData,
      'error_details': errorDetails,
      'duration_ms': durationMs,
    };
  }
}

class LoggingService {
  final SupabaseClient _supabase;
  final StreamController<OperationLog> _logStreamController = StreamController.broadcast();

  LoggingService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  Stream<OperationLog> get logStream => _logStreamController.stream;

  Future<void> log({
    required String userId,
    required OperationType operationType,
    required String targetTable,
    String? targetId,
    required OperationStatus status,
    String? message,
    Map<String, dynamic>? requestData,
    Map<String, dynamic>? responseData,
    String? errorDetails,
    int? durationMs,
  }) async {
    final startTime = DateTime.now();

    try {
      final log = OperationLog(
        id: '',
        userId: userId,
        operationType: operationType,
        targetTable: targetTable,
        targetId: targetId,
        status: status,
        message: message,
        requestData: requestData,
        responseData: responseData,
        errorDetails: errorDetails,
        durationMs: durationMs,
        createdAt: startTime,
      );

      try {
        await _supabase.from('operation_logs').insert(log.toMap());
      } catch (e) {
        print('📝 [LOG] 写入日志失败 (数据库): $e');
      }

      _logStreamController.add(log);

      final statusIcon = status == OperationStatus.success ? '✅' :
                         status == OperationStatus.failed ? '❌' :
                         status == OperationStatus.pending ? '⏳' : 'ℹ️';
      final timeStr = durationMs != null ? '(${durationMs}ms)' : '';
      print('$statusIcon [LOG] ${operationType.displayName} [$operationType] on $targetTable $timeStr');
      if (message != null) print('       $message');
      if (errorDetails != null) print('       ❌ $errorDetails');

    } catch (e) {
      print('❌ [LOG] 记录日志异常: $e');
    }
  }

  Future<void> logSuccess({
    required String userId,
    required OperationType operationType,
    required String targetTable,
    String? targetId,
    String? message,
    Map<String, dynamic>? requestData,
    Map<String, dynamic>? responseData,
    int? durationMs,
  }) async {
    await log(
      userId: userId,
      operationType: operationType,
      targetTable: targetTable,
      targetId: targetId,
      status: OperationStatus.success,
      message: message,
      requestData: requestData,
      responseData: responseData,
      durationMs: durationMs,
    );
  }

  Future<void> logFailure({
    required String userId,
    required OperationType operationType,
    required String targetTable,
    String? targetId,
    String? message,
    Map<String, dynamic>? requestData,
    required String errorDetails,
    int? durationMs,
  }) async {
    await log(
      userId: userId,
      operationType: operationType,
      targetTable: targetTable,
      targetId: targetId,
      status: OperationStatus.failed,
      message: message,
      requestData: requestData,
      errorDetails: errorDetails,
      durationMs: durationMs,
    );
  }

  Future<void> logInfo({
    required String userId,
    required OperationType operationType,
    required String targetTable,
    String? targetId,
    String? message,
    Map<String, dynamic>? requestData,
    Map<String, dynamic>? responseData,
    int? durationMs,
  }) async {
    await log(
      userId: userId,
      operationType: operationType,
      targetTable: targetTable,
      targetId: targetId,
      status: OperationStatus.info,
      message: message,
      requestData: requestData,
      responseData: responseData,
      durationMs: durationMs,
    );
  }

  Future<void> logMessageSend({
    required String userId,
    required String content,
    String? messageId,
    bool success = true,
    String? error,
  }) async {
    await log(
      userId: userId,
      operationType: OperationType.message_send,
      targetTable: 'messages',
      targetId: messageId,
      status: success ? OperationStatus.success : OperationStatus.failed,
      message: success ? '发送消息成功' : '发送消息失败',
      requestData: {'content': content},
      errorDetails: error,
    );
  }

  Future<void> logMessageSave({
    required String userId,
    required String role,
    required String content,
    String? messageId,
    bool success = true,
    String? error,
  }) async {
    await log(
      userId: userId,
      operationType: OperationType.message_save,
      targetTable: 'messages',
      targetId: messageId,
      status: success ? OperationStatus.success : OperationStatus.failed,
      message: success ? '保存${role == 'user' ? '用户' : 'AI'}消息成功' : '保存消息失败',
      requestData: {'role': role, 'content': content},
      errorDetails: error,
    );
  }

  Future<void> logAiResponse({
    required String userId,
    required String? messageId,
    String? content,
    int? durationMs,
    bool success = true,
    String? error,
  }) async {
    await log(
      userId: userId,
      operationType: success ? OperationType.ai_response : OperationType.ai_error,
      targetTable: 'messages',
      targetId: messageId,
      status: success ? OperationStatus.success : OperationStatus.failed,
      message: success ? 'AI响应成功' : 'AI响应失败',
      responseData: success ? {'content_length': content?.length ?? 0} : null,
      errorDetails: error,
      durationMs: durationMs,
    );
  }

  Future<void> logAuthLogin({
    required String userId,
    String? email,
    bool success = true,
    String? error,
  }) async {
    await log(
      userId: userId,
      operationType: success ? OperationType.auth_login_success : OperationType.auth_login_failure,
      targetTable: 'profiles',
      targetId: userId,
      status: success ? OperationStatus.success : OperationStatus.failed,
      message: success ? '登录成功' : '登录失败',
      requestData: email != null ? {'email': email} : null,
      errorDetails: error,
    );
  }

  Future<void> logAuthRegister({
    required String userId,
    String? email,
    bool success = true,
    String? error,
  }) async {
    await log(
      userId: userId,
      operationType: success ? OperationType.auth_register_success : OperationType.auth_register_failure,
      targetTable: 'profiles',
      targetId: userId,
      status: success ? OperationStatus.success : OperationStatus.failed,
      message: success ? '注册成功' : '注册失败',
      requestData: email != null ? {'email': email} : null,
      errorDetails: error,
    );
  }

  Future<void> logAuthLogout({
    required String userId,
  }) async {
    await log(
      userId: userId,
      operationType: OperationType.auth_logout,
      targetTable: 'profiles',
      targetId: userId,
      status: OperationStatus.success,
      message: '登出成功',
    );
  }

  Future<void> logProfileUpdate({
    required String userId,
    Map<String, dynamic> changes = const {},
    bool success = true,
    String? error,
  }) async {
    await log(
      userId: userId,
      operationType: success ? OperationType.profile_update_success : OperationType.profile_update_failure,
      targetTable: 'profiles',
      targetId: userId,
      status: success ? OperationStatus.success : OperationStatus.failed,
      message: success ? '更新资料成功' : '更新资料失败',
      requestData: changes,
      errorDetails: error,
    );
  }

  Future<void> logSystemStartup({
    required String userId,
    String? message,
  }) async {
    await log(
      userId: userId,
      operationType: OperationType.system_startup,
      targetTable: 'system',
      status: OperationStatus.info,
      message: message ?? '应用启动',
    );
  }

  Future<void> logSystemError({
    required String userId,
    required String error,
    String? context,
  }) async {
    await log(
      userId: userId,
      operationType: OperationType.system_error,
      targetTable: 'system',
      status: OperationStatus.failed,
      message: context,
      errorDetails: error,
    );
  }

  void close() {
    _logStreamController.close();
  }
}
