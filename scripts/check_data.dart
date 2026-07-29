import 'dart:convert';
import 'dart:io';

late String supabaseUrl;
late String serviceKey;

void main() async {
  final envFile = File('.env');
  if (!envFile.existsSync()) {
    print('❌ .env 文件不存在');
    exit(1);
  }

  final env = <String, String>{};
  for (final line in envFile.readAsLinesSync()) {
    if (line.contains('=') && !line.startsWith('#')) {
      final idx = line.indexOf('=');
      env[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }
  }

  supabaseUrl = env['SUPABASE_URL'] ?? '';
  serviceKey = env['SUPABASE_SERVICE_ROLE_KEY'] ?? '';

  final client = HttpClient();
  
  try {
    print('=== 用户消息列表 ===');
    await fetchAndPrint(client, 'messages', {'role': 'eq.user'}, ['id', 'content', 'extracted', 'extraction_error', 'created_at']);
    
    print('\n=== 事实组列表 ===');
    await fetchAndPrint(client, 'fact_groups', {}, ['id', 'message_id', 'summary', 'fact_count', 'created_at']);
    
    print('\n=== 提取的事实列表 ===');
    await fetchAndPrint(client, 'extracted_facts', {}, ['id', 'message_id', 'fact_group_id', 'fact_type', 'fact_key', 'fact_value']);
    
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}

Future<void> fetchAndPrint(HttpClient client, String table, Map<String, String> filters, List<String> columns) async {
  var url = '$supabaseUrl/rest/v1/$table?select=${columns.join(',')}&order=created_at.desc';
  if (filters.isNotEmpty) {
    url += '&' + filters.entries.map((e) => '${e.key}=${e.value}').join('&');
  }
  
  final request = await client.getUrl(Uri.parse(url));
  request.headers.add('Authorization', 'Bearer $serviceKey');
  request.headers.add('apikey', serviceKey);
  
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  
  if (response.statusCode != 200) {
    print('请求失败: ${response.statusCode} - $body');
    return;
  }
  
  final data = jsonDecode(body) as List<dynamic>;
  print('总数: ${data.length}');
  
  final limit = data.length < 5 ? data.length : 5;
  for (int i = 0; i < limit; i++) {
    final item = data[i] as Map<String, dynamic>;
    final parts = <String>[];
    for (final e in item.entries) {
      var val = e.value?.toString() ?? 'null';
      if (val.length > 50) val = val.substring(0, 50) + '...';
      parts.add('${e.key}: $val');
    }
    print('[$i] ${parts.join(', ')}');
  }
}
