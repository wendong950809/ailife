import 'dart:io';

void main() async {
  final server = await HttpServer.bind('0.0.0.0', 8080);
  print('Server running at http://127.0.0.1:8080');

  await for (final request in server) {
    try {
      await handleRequest(request);
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }
}

Future<void> handleRequest(HttpRequest request) async {
  final response = request.response;
  var requestPath = request.uri.path;

  if (requestPath == '/') {
    requestPath = '/index.html';
  }

  if (requestPath.startsWith('/')) {
    requestPath = requestPath.substring(1);
  }

  final filePath = 'build/web/$requestPath';
  final file = File(filePath);

  if (await file.exists()) {
    final contentType = _getContentType(filePath);
    response.headers.contentType = contentType;
    await file.openRead().pipe(response);
  } else {
    final indexFile = File('build/web/index.html');
    if (await indexFile.exists()) {
      response.headers.contentType = ContentType.html;
      await indexFile.openRead().pipe(response);
    } else {
      response.statusCode = HttpStatus.notFound;
      response.write('404 Not Found');
      await response.close();
    }
  }
}

ContentType _getContentType(String filePath) {
  final ext = filePath.toLowerCase().split('.').last;
  switch (ext) {
    case 'html':
      return ContentType.html;
    case 'css':
      return ContentType('text', 'css');
    case 'js':
      return ContentType('application', 'javascript');
    case 'json':
      return ContentType.json;
    case 'png':
      return ContentType('image', 'png');
    case 'jpg':
    case 'jpeg':
      return ContentType('image', 'jpeg');
    case 'gif':
      return ContentType('image', 'gif');
    case 'svg':
      return ContentType('image', 'svg+xml');
    case 'ico':
      return ContentType('image', 'x-icon');
    case 'woff':
      return ContentType('font', 'woff');
    case 'woff2':
      return ContentType('font', 'woff2');
    case 'ttf':
      return ContentType('font', 'ttf');
    default:
      return ContentType('application', 'octet-stream');
  }
}
