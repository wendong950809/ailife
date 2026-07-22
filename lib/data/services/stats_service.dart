import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/memory.dart';

/// ============================================
/// 数据统计服务
/// ============================================
/// 从数据库实时统计各种数据，供各页面展示
/// 所有统计都基于 extracted_facts 和 messages 表
/// ============================================

class StatsService {
  final SupabaseClient _supabase;

  StatsService({SupabaseClient? supabase})
      : _supabase = supabase ?? Supabase.instance.client;

  String? _currentUserId;

  String? get _userId {
    _currentUserId ??= _supabase.auth.currentUser?.id;
    return _currentUserId;
  }

  void _refreshUser() {
    _currentUserId = _supabase.auth.currentUser?.id;
  }

  /// ============================================
  /// 首页 - 每日简报统计
  /// ============================================
  /// 返回 {goals: N, events: N, reminders: N}
  /// ============================================
  Future<Map<String, int>> getDailyBriefing() async {
    _refreshUser();
    if (_userId == null) return {'goals': 0, 'events': 0, 'reminders': 0};

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      final response = await _supabase
          .from('extracted_facts')
          .select('fact_type')
          .eq('user_id', _userId!)
          .gte('created_at', '$todayStr 00:00:00')
          .lte('created_at', '$todayStr 23:59:59');

      int goals = 0;
      int events = 0;
      int reminders = 0;

      if (response is List) {
        for (final item in response) {
          final type = item['fact_type'] as String?;
          if (type == 'goal') goals++;
          else if (type == 'event') events++;
          else if (type == 'time') reminders++;
        }
      }

      // 如果今天没有数据，给默认值避免页面太空
      return {
        'goals': goals > 0 ? goals : 0,
        'events': events > 0 ? events : 0,
        'reminders': reminders > 0 ? reminders : 0,
      };
    } catch (e) {
      print('[StatsService] 每日简报统计失败: $e');
      return {'goals': 0, 'events': 0, 'reminders': 0};
    }
  }

  /// ============================================
  /// 首页 - 人生状态评分
  /// ============================================
  /// 基于各事实类型数量计算综合评分
  /// ============================================
  Future<Map<String, dynamic>> getLifeScore() async {
    _refreshUser();
    if (_userId == null) {
      return {
        'total': 0,
        'work': 0.0,
        'family': 0.0,
        'growth': 0.0,
        'health': 0.0,
      };
    }

    try {
      // 统计各类事实数量
      final response = await _supabase
          .from('extracted_facts')
          .select('fact_type')
          .eq('user_id', _userId!);

      Map<String, int> counts = {
        'work': 0,
        'family': 0,
        'skill': 0,
        'health': 0,
      };

      if (response is List) {
        for (final item in response) {
          final type = item['fact_type'] as String?;
          if (type != null && counts.containsKey(type)) {
            counts[type] = counts[type]! + 1;
          }
        }
      }

      // 简单的评分算法：每类最多100分，每10条事实加10分，上限100
      double calcScore(int count) {
        if (count <= 0) return 0.3;
        final score = (count * 0.1).clamp(0.0, 1.0);
        return score < 0.3 ? 0.3 : score;
      }

      double workScore = calcScore(counts['work']!);
      double familyScore = calcScore(counts['family']!);
      double growthScore = calcScore(counts['skill']!);
      double healthScore = calcScore(counts['health']!);

      double total = ((workScore + familyScore + growthScore + healthScore) / 4 * 100).roundToDouble();

      return {
        'total': total.toInt(),
        'work': workScore,
        'family': familyScore,
        'growth': growthScore,
        'health': healthScore,
      };
    } catch (e) {
      print('[StatsService] 人生状态评分失败: $e');
      return {
        'total': 0,
        'work': 0.0,
        'family': 0.0,
        'growth': 0.0,
        'health': 0.0,
      };
    }
  }

  /// ============================================
  /// 我的页面 - 角色标签
  /// ============================================
  Future<List<String>> getPersonRoles() async {
    _refreshUser();
    if (_userId == null) return [];

    try {
      final response = await _supabase
          .from('extracted_facts')
          .select('fact_value')
          .eq('user_id', _userId!)
          .eq('fact_type', 'person')
          .eq('fact_key', 'role')
          .limit(10);

      final roles = <String>{};
      if (response is List) {
        for (final item in response) {
          final val = item['fact_value'] as String?;
          if (val != null && val.isNotEmpty) {
            roles.add(val);
          }
        }
      }
      return roles.toList();
    } catch (e) {
      print('[StatsService] 角色标签失败: $e');
      return [];
    }
  }

  /// ============================================
  /// 我的页面 - 各维度统计数字
  /// ============================================
  Future<Map<String, int>> getLifeDimensions() async {
    _refreshUser();
    if (_userId == null) {
      return {'relations': 0, 'goals': 0, 'events': 0, 'values': 0};
    }

    try {
      final response = await _supabase
          .from('extracted_facts')
          .select('fact_type, fact_key')
          .eq('user_id', _userId!);

      int relations = 0;
      int goals = 0;
      int events = 0;
      int values = 0;

      if (response is List) {
        final seenRelations = <String>{};
        final seenGoals = <String>{};
        for (final item in response) {
          final type = item['fact_type'] as String?;
          final key = item['fact_key'] as String?;
          if (type == 'person' && key == 'relation') {
            relations++;
            seenRelations.add(key ?? '');
          } else if (type == 'goal') {
            goals++;
            seenGoals.add(key ?? '');
          } else if (type == 'event') {
            events++;
          } else if (type == 'value' || key == 'value') {
            values++;
          }
        }
      }

      return {
        'relations': relations,
        'goals': goals,
        'events': events,
        'values': values > 0 ? values : 5,
      };
    } catch (e) {
      print('[StatsService] 维度统计失败: $e');
      return {'relations': 0, 'goals': 0, 'events': 0, 'values': 0};
    }
  }

  /// ============================================
  /// 我的页面 - 数字自我成长
  /// ============================================
  Future<Map<String, dynamic>> getGrowthStats() async {
    _refreshUser();
    if (_userId == null) {
      return {'days': 0, 'facts': 0, 'understanding': 0.0};
    }

    try {
      // 获取最早的消息时间
      final firstMsg = await _supabase
          .from('messages')
          .select('created_at')
          .eq('user_id', _userId!)
          .order('created_at', ascending: true)
          .limit(1);

      int days = 1;
      if (firstMsg is List && firstMsg.isNotEmpty) {
        final firstDate = DateTime.parse(firstMsg[0]['created_at'] as String);
        days = DateTime.now().difference(firstDate).inDays + 1;
      }

      // 获取事实总数
      final factsCount = await _supabase
          .from('extracted_facts')
          .select('id')
          .eq('user_id', _userId!)
          .then((r) => r is List ? r.length : 0)
          .catchError((e) {
        print('[StatsService] 事实统计失败: $e');
        return 0;
      });

      // 理解度算法：基础10%，每10条事实加3%，上限90%
      double understanding = 0.1 + (factsCount * 0.03);
      if (understanding > 0.9) understanding = 0.9;

      return {
        'days': days,
        'facts': factsCount,
        'understanding': understanding,
      };
    } catch (e) {
      print('[StatsService] 成长统计失败: $e');
      return {'days': 0, 'facts': 0, 'understanding': 0.0};
    }
  }

  /// ============================================
  /// 时间线 - 记忆列表
  /// ============================================
  Future<List<Memory>> getMemories({int limit = 30}) async {
    _refreshUser();
    if (_userId == null) return [];

    try {
      final response = await _supabase
          .from('memories')
          .select()
          .eq('user_id', _userId!)
          .order('created_at', ascending: false)
          .limit(limit);

      if (response is List && response.isNotEmpty) {
        return response.map((m) => Memory.fromMap(m)).toList();
      }
      return [];
    } catch (e) {
      print('[StatsService] 记忆列表失败: $e');
      return [];
    }
  }

  /// ============================================
  /// 首页 - 今日重点（从extracted_facts提取的目标/事件）
  /// ============================================
  Future<List<Map<String, dynamic>>> getTodayFocus() async {
    _refreshUser();
    if (_userId == null) return [];

    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      final response = await _supabase
          .from('extracted_facts')
          .select()
          .eq('user_id', _userId!)
          .gte('created_at', '$todayStr 00:00:00')
          .lte('created_at', '$todayStr 23:59:59')
          .inFilter('fact_type', ['goal', 'event', 'work'])
          .order('created_at', ascending: false)
          .limit(10);

      if (response is List && response.isNotEmpty) {
        return response.map((item) {
          return {
            'title': item['fact_value'] as String? ?? '',
            'category': item['fact_type'] as String? ?? 'other',
            'completed': false,
          };
        }).toList();
      }
      return [];
    } catch (e) {
      print('[StatsService] 今日重点失败: $e');
      return [];
    }
  }

  /// ============================================
  /// 首页 - AI 洞察（基于最近数据生成简单文案）
  /// ============================================
  Future<String> getAiInsight() async {
    _refreshUser();
    if (_userId == null) return '';

    try {
      final stats = await getLifeDimensions();
      final total = stats['events']! + stats['goals']! + stats['relations']!;

      if (total == 0) {
        return '多跟我聊聊你的生活吧，我会帮你记录和分析每一天。';
      }

      StringBuffer sb = StringBuffer();
      sb.write('最近你记录了 ${stats['events']} 个事件');
      if (stats['goals']! > 0) {
        sb.write('，有 ${stats['goals']} 个目标在推进');
      }
      if (stats['relations']! > 0) {
        sb.write('，涉及 ${stats['relations']} 位重要人物');
      }
      sb.write('。继续保持记录，我会帮你发现更多成长轨迹。');

      return sb.toString();
    } catch (e) {
      return '';
    }
  }
}
