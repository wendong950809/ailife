import 'dart:io';
import 'dart:convert';

void main() async {
  // 读取 .env
  final envFile = File('.env');
  final env = <String, String>{};
  for (final line in envFile.readAsLinesSync()) {
    if (line.contains('=') && !line.startsWith('#')) {
      final idx = line.indexOf('=');
      env[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }
  }

  final url = env['SUPABASE_URL'] ?? '';
  final anonKey = env['SUPABASE_ANON_KEY'] ?? '';
  final serviceKey = env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';

  print('URL: $url');
  print('Anon Key: ${anonKey.substring(0, anonKey.length > 20 ? 20 : anonKey.length)}...');
  print('Service Key: ${serviceKey.substring(0, serviceKey.length > 20 ? 20 : serviceKey.length)}...');
  print('');

  // 测试1: 用 anon key 查询 profiles
  print('--- 测试1: anon key 查询 profiles ---');
  await testRequest(url, anonKey, 'profiles');

  // 测试2: 用 service key 查询 profiles
  print('--- 测试2: service key 查询 profiles ---');
  await testRequest(url, serviceKey, 'profiles');

  // 测试3: 用 service key 查询 messages
  print('--- 测试3: service key 查询 messages ---');
  await testRequest(url, serviceKey, 'messages');

  exit(0);
}

Future<void> testRequest(String url, String key, String table) async {
  try {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    final request = await client.getUrl(
      Uri.parse('$url/rest/v1/$table?select=id&limit=1'),
    );
    request.headers.add('apikey', key);
    request.headers.add('Authorization', 'Bearer $key');

    final response = await request.close().timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        print('  ❌ 超时!');
        throw Exception('请求超时');
      },
    );

    final body = await response.transform(utf8.decoder).join();
    client.close();

    print('  状态码: ${response.statusCode}');
    if (response.statusCode == 200) {
      final data = jsonDecode(body);
      print('  ✅ 成功: $data');
    } else {
      print('  ❌ 失败: $body');
    }
  } catch (e) {
    print('  ❌ 异常: $e');
  }
  print('');
}
