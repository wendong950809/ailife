import 'dart:io';
import 'dart:convert';

void main() async {
  final env = File('.env').readAsStringSync();
  final url = env.split('SUPABASE_URL=')[1].split('\n')[0].trim();
  final anonKey = env.split('SUPABASE_ANON_KEY=')[1].split('\n')[0].trim();
  
  final email = 'wendong0809@qq.com';
  final password = 'amman123';
  
  print('🔐 测试登录: $email');
  print('🔑 密码: $password');
  print('');
  
  final client = HttpClient();
  final req = await client.postUrl(
    Uri.parse('$url/auth/v1/token?grant_type=password'),
  );
  req.headers.add('apikey', anonKey);
  req.headers.add('Content-Type', 'application/json');
  
  req.add(utf8.encode(jsonEncode({
    'email': email,
    'password': password,
  })));
  
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  
  print('状态码: ${res.statusCode}');
  print('响应: $body');
  
  client.close();
}
