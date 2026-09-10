import 'dart:convert';
import 'dart:io';

class SyncServer {
  HttpServer? _server;

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) {
      return;
    }

    _server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      8080,
    );

    _server!.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'GET' &&
          request.uri.path == '/api/health') {
        await _sendJson(
          request.response,
          200,
          {
            'status': 'ok',
            'service': 'leo-desk-sync',
          },
        );
        return;
      }

      await _sendJson(
        request.response,
        404,
        {
          'error': 'Not found',
        },
      );
    } catch (e) {
      await _sendJson(
        request.response,
        500,
        {
          'error': 'Internal server error',
        },
      );
    }
  }

  Future<void> _sendJson(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> data,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    await response.close();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}