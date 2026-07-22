import 'dart:io';
import 'dart:convert';

void main() async {
  final envFile = File('.env');
  final env = <String, String>{};
  for (final line in envFile.readAsLinesSync()) {
    if (line.contains('=') && !line.startsWith('#')) {
      final idx = line.indexOf('=');
      env[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }
  }

  final url = env['SUPABASE_URL'] ?? '';
  final serviceKey = env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';

  print('🔍 步骤1: 查询用户列表');
  final users = await fetchUsers(url, serviceKey);
  if (users.isEmpty) {
    print('❌ 未找到用户，请先注册');
    exit(1);
  }

  print('✅ 找到 ${users.length} 个用户');
  for (var i = 0; i < users.length && i < 3; i++) {
    print('   ${i + 1}. ${users[i]['email'] ?? users[i]['id']}');
  }

  if (users.length >= 2) {
    print('\n📥 步骤2: 为用户1插入mock数据');
    await insertMockTimeline(url, serviceKey, users[0]['id'], '张三');

    print('\n📥 步骤3: 为用户2插入mock数据');
    await insertMockTimeline(url, serviceKey, users[1]['id'], '李四');
  } else if (users.length == 1) {
    print('\n📥 步骤2: 为用户1插入mock数据');
    await insertMockTimeline(url, serviceKey, users[0]['id'], '用户1');
  }

  print('\n🎉 Mock数据插入完成！');
  exit(0);
}

Future<List<Map<String, dynamic>>> fetchUsers(String url, String key) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    final request = await client.getUrl(
      Uri.parse('$url/auth/v1/admin/users'),
    );
    request.headers.add('apikey', key);
    request.headers.add('Authorization', 'Bearer $key');

    final response = await request.close().timeout(const Duration(seconds: 15));
    final body = await response.transform(utf8.decoder).join();
    client.close();

    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(jsonDecode(body));
      final users = List<Map<String, dynamic>>.from(data['users'] ?? []);
      return users.map((u) => {
        'id': u['id'],
        'email': u['email'] ?? u['id'],
      }).toList();
    } else {
      print('  ❌ 查询失败: $body');
      return [];
    }
  } catch (e) {
    print('  ❌ 异常: $e');
    return [];
  }
}

Future<void> insertMockTimeline(String url, String key, String userId, String userName) async {
  final now = DateTime.now();
  final events = generateMockEvents(userName, now);

  for (var i = 0; i < events.length; i++) {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(Uri.parse('$url/rest/v1/timeline'));
      request.headers.add('apikey', key);
      request.headers.add('Authorization', 'Bearer $key');
      request.headers.add('Content-Type', 'application/json');
      request.headers.add('Prefer', 'return=representation');

      final event = events[i];
      event['user_id'] = userId;

      final jsonStr = jsonEncode(event);
      request.add(utf8.encode(jsonStr));
      final response = await request.close().timeout(const Duration(seconds: 15));
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 201) {
        print('  ✅ ${i + 1}/${events.length}: ${event['title']}');
      } else {
        print('  ❌ ${i + 1}/${events.length}: 失败 - $body');
      }
    } catch (e) {
      print('  ❌ ${i + 1}/${events.length}: 异常 - $e');
    }
  }
}

List<Map<String, dynamic>> generateMockEvents(String userName, DateTime now) {
  return [
    {
      'title': '参加产品发布会',
      'summary': '$userName参加了公司年度产品发布会，见到了很多行业大佬，收获颇丰。',
      'occurred_at': now.subtract(const Duration(days: 1)).toIso8601String(),
      'time_precision': 'day',
      'icon': '🎤',
      'event_source': 'calendar',
      'raw_content': '今天参加了产品发布会，很精彩',
    },
    {
      'title': '和家人吃火锅',
      'summary': '$userName和家人一起去吃了火锅，聊了很多家常，感觉很温馨。',
      'occurred_at': now.subtract(const Duration(days: 3)).toIso8601String(),
      'time_precision': 'day',
      'icon': '🍲',
      'event_source': 'chat',
      'raw_content': '昨天和家人吃了顿火锅，很开心',
    },
    {
      'title': '完成马拉松训练',
      'summary': '$userName完成了本周的马拉松训练计划，跑了15公里，状态不错。',
      'occurred_at': now.subtract(const Duration(days: 5)).toIso8601String(),
      'time_precision': 'day',
      'icon': '🏃',
      'event_source': 'health',
      'raw_content': '今天跑了15公里，完成训练',
    },
    {
      'title': '阅读《置身事内》',
      'summary': '$userName读完了《置身事内》这本书，对中国经济有了更深的理解。',
      'occurred_at': now.subtract(const Duration(days: 7)).toIso8601String(),
      'time_precision': 'week',
      'icon': '📚',
      'event_source': 'document',
      'raw_content': '这周读完了《置身事内》',
    },
    {
      'title': '学习Flutter进阶',
      'summary': '$userName花了一周时间学习Flutter高级特性，包括状态管理和性能优化。',
      'occurred_at': now.subtract(const Duration(days: 10)).toIso8601String(),
      'time_precision': 'week',
      'icon': '💻',
      'event_source': 'chat',
      'raw_content': '最近在学习Flutter进阶知识',
    },
    {
      'title': '女儿学会骑车',
      'summary': '$userName陪女儿练习骑车，她终于学会了自己骑，不需要辅助轮了。',
      'occurred_at': now.subtract(const Duration(days: 14)).toIso8601String(),
      'time_precision': 'day',
      'icon': '🚴',
      'event_source': 'chat',
      'raw_content': '女儿今天学会骑车了！',
    },
    {
      'title': '月度总结会议',
      'summary': '$userName参加了部门月度总结会议，汇报了本月的工作成果。',
      'occurred_at': now.subtract(const Duration(days: 20)).toIso8601String(),
      'time_precision': 'day',
      'icon': '📊',
      'event_source': 'calendar',
      'raw_content': '今天开了月度总结会',
    },
    {
      'title': '家庭旅行',
      'summary': '$userName全家去海边旅行了一周，孩子们玩得很开心，自己也放松了不少。',
      'occurred_at': now.subtract(const Duration(days: 30)).toIso8601String(),
      'time_precision': 'month',
      'icon': '🌊',
      'event_source': 'chat',
      'raw_content': '上个月全家去海边玩了一周',
    },
    {
      'title': '项目上线',
      'summary': '$userName负责的项目正式上线，经过了三个月的努力，终于看到了成果。',
      'occurred_at': now.subtract(const Duration(days: 45)).toIso8601String(),
      'time_precision': 'month',
      'icon': '🚀',
      'event_source': 'document',
      'raw_content': '项目终于上线了！',
    },
    {
      'title': '年度体检',
      'summary': '$userName去医院做了年度体检，各项指标都很正常，身体状况良好。',
      'occurred_at': now.subtract(const Duration(days: 60)).toIso8601String(),
      'time_precision': 'month',
      'icon': '🏥',
      'event_source': 'health',
      'raw_content': '做了年度体检，身体很健康',
    },
    {
      'title': '生日聚会',
      'summary': '$userName过了一个难忘的生日，朋友们给了很多惊喜。',
      'occurred_at': now.subtract(const Duration(days: 90)).toIso8601String(),
      'time_precision': 'day',
      'icon': '🎂',
      'event_source': 'chat',
      'raw_content': '昨天生日，朋友们给了很多惊喜',
    },
  ];
}
