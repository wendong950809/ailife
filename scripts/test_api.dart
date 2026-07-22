import 'dart:io';
import 'dart:convert';

void main() async {
  final env = File('.env').readAsStringSync();
  final url = env.split('SUPABASE_URL=')[1].split('\n')[0].trim();
  final key = env.split('SUPABASE_SERVICE_ROLE_KEY=')[1].split('\n')[0].trim();
  
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse('$url/auth/v1/admin/users'));
  req.headers.add('apikey', key);
  req.headers.add('Authorization', 'Bearer $key');
  
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  
  print('Status: ${res.statusCode}');
  print('Body: $body');
  
  try {
    final data = jsonDecode(body);
    print('Type: ${data.runtimeType}');
    if (data is List) {
      print('Length: ${data.length}');
      if (data.isNotEmpty) {
        print('First: ${data[0]}');
      }
    } else if (data is Map) {
      print('Keys: ${data.keys}');
    }
  } catch (e) {
    print('Parse error: $e');
  }
  
  client.close();
}
