import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/core/config/app_config.dart';

class StorageUploadService {
  const StorageUploadService._();

  static String? objectPathFromStorageUrl(String bucket, Object? value) {
    final rawValue = value?.toString();
    if (rawValue == null || rawValue.isEmpty) return null;

    final uri = Uri.tryParse(rawValue);
    if (uri == null || !uri.hasScheme) return rawValue;

    final segments = uri.pathSegments;
    final objectIndex = segments.indexOf('object');
    if (objectIndex == -1) {
      final bucketIndex = segments.indexOf(bucket);
      if (bucketIndex == -1) return null;
      final objectPath = segments.skip(bucketIndex + 1).join('/');
      return objectPath.isEmpty ? null : objectPath;
    }

    var bucketIndex = objectIndex + 1;
    if (bucketIndex < segments.length &&
        const {'public', 'private', 'sign'}.contains(segments[bucketIndex])) {
      bucketIndex++;
    }
    if (bucketIndex >= segments.length || segments[bucketIndex] != bucket) {
      return null;
    }

    final objectPath = segments.skip(bucketIndex + 1).join('/');
    return objectPath.isEmpty ? null : objectPath;
  }

  static Future<void> uploadBinary({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    required void Function(int uploadedBytes, int totalBytes) onProgress,
  }) async {
    final uploadUrl = await _requestUrl(
      action: 'upload',
      bucket: bucket,
      path: path,
      contentType: contentType,
    );
    final uri = Uri.parse(uploadUrl);
    final request = http.StreamedRequest('PUT', uri)
      ..contentLength = bytes.length
      ..headers['Content-Type'] = contentType;
    final client = http.Client();
    var requestBodyClosed = false;
    try {
      final responseFuture = client.send(request);
      var uploadedBytes = 0;
      const chunkSize = 64 * 1024;
      onProgress(0, bytes.length);

      while (uploadedBytes < bytes.length) {
        final nextOffset = (uploadedBytes + chunkSize).clamp(0, bytes.length);
        request.sink.add(
          Uint8List.sublistView(bytes, uploadedBytes, nextOffset),
        );
        uploadedBytes = nextOffset;
        onProgress(uploadedBytes, bytes.length);
        await Future<void>.delayed(Duration.zero);
      }

      requestBodyClosed = true;
      await request.sink.close();
      final streamedResponse = await responseFuture;
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'S3 upload failed (${response.statusCode}): ${response.body}',
          uri,
        );
      }
    } finally {
      if (!requestBodyClosed) await request.sink.close();
      client.close();
    }
  }

  static Future<String> createSignedUrl({
    required String bucket,
    required String path,
    int expiresIn = 3600,
  }) {
    return _requestUrl(
      action: 'read',
      bucket: bucket,
      path: path,
      expiresIn: expiresIn,
    );
  }

  static Future<String> getPublicUrl({
    required String bucket,
    required String path,
  }) {
    return _requestUrl(action: 'public_url', bucket: bucket, path: path);
  }

  static Future<void> remove({
    required String bucket,
    required String path,
  }) async {
    final uri = Uri.parse(
      await _requestUrl(action: 'delete', bucket: bucket, path: path),
    );
    final client = http.Client();
    try {
      final response = await client.delete(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'S3 delete failed (${response.statusCode}): ${response.body}',
          uri,
        );
      }
    } finally {
      client.close();
    }
  }

  static Future<String> _requestUrl({
    required String action,
    required String bucket,
    required String path,
    String? contentType,
    int? expiresIn,
  }) async {
    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Нет активной сессии для доступа к S3');
    }

    final client = http.Client();
    try {
      final response = await client.post(
        Uri.parse(AppConfig.s3StorageSigning),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'action': action,
          'bucket': bucket,
          'path': path,
          if (contentType != null) 'content_type': contentType,
          if (expiresIn != null) 'expires_in': expiresIn,
        }),
      );
      final body = jsonDecode(response.body);
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          body is! Map<String, dynamic> ||
          body['url'] is! String) {
        final message = body is Map<String, dynamic>
            ? body['message']?.toString()
            : null;
        throw http.ClientException(
          message ?? 'Не удалось получить ссылку S3 (${response.statusCode})',
          Uri.parse(AppConfig.s3StorageSigning),
        );
      }
      return body['url'] as String;
    } finally {
      client.close();
    }
  }
}
