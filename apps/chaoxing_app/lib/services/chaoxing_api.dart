import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_config.dart';
import '../models/app_sync_response.dart';

class ChaoxingApiException implements Exception {
  const ChaoxingApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() {
    return statusCode == null ? message : '$message ($statusCode)';
  }
}

class ChaoxingApi {
  ChaoxingApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AppSyncResponse> fetchAppSync(AppConfig config) async {
    final uri = _buildUri(config.baseUrl);
    final response = await _client.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer ${config.token.trim()}',
      },
    );

    if (response.statusCode == 401) {
      throw const ChaoxingApiException('Token 不正确或已过期', statusCode: 401);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChaoxingApiException('同步失败，请稍后重试', statusCode: response.statusCode);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const ChaoxingApiException('服务端返回格式不正确');
    }
    return AppSyncResponse.fromJson(decoded);
  }

  Uri _buildUri(String baseUrl) {
    final trimmed = baseUrl.trim();
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final uri = Uri.tryParse('$normalized/app/sync');
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const ChaoxingApiException('Worker URL 不正确');
    }
    return uri;
  }
}
