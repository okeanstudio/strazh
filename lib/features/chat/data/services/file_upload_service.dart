import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:url_launcher/url_launcher.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

class FileUploadService {
  static const String _bucketName = 'chat_files';

  Future<String> uploadFile({
    required Uint8List fileBytes,
    required String fileName,
    required String chatId,
    required String userId,
    void Function(int uploadedBytes, int totalBytes)? onProgress,
  }) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('Нет авторизации');
      }

      final cleanFileName = _cleanFileName(fileName);
      final filePath =
          '$chatId/${DateTime.now().millisecondsSinceEpoch}_$cleanFileName';

      await StorageUploadService.uploadBinary(
        bucket: _bucketName,
        path: filePath,
        bytes: fileBytes,
        contentType: _getMimeType(cleanFileName),
        onProgress: onProgress ?? (_, _) {},
      );

      return filePath;
    } catch (e) {
      throw Exception('Ошибка загрузки файла: $e');
    }
  }

  String _cleanFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  String _getMimeType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':
        return 'text/plain';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/x-rar-compressed';
      case '7z':
        return 'application/x-7z-compressed';
      case 'json':
        return 'application/json';
      case 'xml':
        return 'application/xml';
      case 'csv':
        return 'text/csv';
      default:
        return 'application/octet-stream';
    }
  }

  static Future<file_selector.XFile?> pickFile() async {
    try {
      const types = [
        file_selector.XTypeGroup(
          label: 'Документы',
          extensions: [
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'ppt',
            'pptx',
            'txt',
          ],
        ),
        file_selector.XTypeGroup(
          label: 'Архивы',
          extensions: ['zip', 'rar', '7z'],
        ),
        file_selector.XTypeGroup(
          label: 'Данные',
          extensions: ['json', 'xml', 'csv'],
        ),
        file_selector.XTypeGroup(label: 'Все файлы', extensions: ['*']),
      ];

      final file = await file_selector.openFile(acceptedTypeGroups: types);
      return file;
    } catch (e) {
      return null;
    }
  }

  static Future<void> downloadFile(String url, String fileName) async {
    try {
      // Просто открываем URL в браузере для скачивания
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Не удалось открыть ссылку');
      }
    } catch (e) {
      throw Exception('Ошибка скачивания: $e');
    }
  }
}
