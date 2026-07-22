import 'dart:convert';
import 'dart:io';

void main() async {
  final client = HttpClient();
  
  try {
    final request = await client.postUrl(Uri.parse('http://127.0.0.1:8081/api/reextract'));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'message_id': 'test'}));
    
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    
    print('Status: ${response.statusCode}');
    print('Response: $body');
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
