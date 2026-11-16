import 'package:flutter/material.dart';
import 'package:strazh/features/chat/data/services/file_upload_service.dart';
import 'package:strazh/shared/presentation/widgets/toast.dart';

class FileMessageBubble extends StatelessWidget {
  final String fileName;
  final String fileUrl;
  final int? fileSize;
  final bool isMe;

  const FileMessageBubble({
    super.key,
    required this.fileName,
    required this.fileUrl,
    this.fileSize,
    required this.isMe,
  });

  String _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf': return '📄';
      case 'doc': case 'docx': return '📝';
      case 'xls': case 'xlsx': return '📊';
      case 'ppt': case 'pptx': return '📑';
      case 'zip': case 'rar': case '7z': return '📦';
      case 'txt': return '📃';
      case 'json': case 'xml': case 'csv': return '📋';
      default: return '📎';
    }
  }

  Color _getFileColor(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf': return Colors.red;
      case 'doc': case 'docx': return Colors.blue;
      case 'xls': case 'xlsx': return Colors.green;
      case 'ppt': case 'pptx': return Colors.orange;
      case 'zip': case 'rar': case '7z': return Colors.purple;
      case 'txt': return Colors.grey;
      default: return Colors.grey;
    }
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        try {
          await FileUploadService.downloadFile(fileUrl, fileName);
          if (context.mounted) {
            Toast.success(context, 'Файл скачан');
          }
        } catch (e) {
          if (context.mounted) {
            Toast.error(context, 'Ошибка скачивания: $e');
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe 
              ? const Color(0xFF1A73E8).withValues(alpha: 0.15)
              : const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getFileColor(fileName).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getFileColor(fileName).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  _getFileIcon(fileName),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 180,
                  child: Text(
                    fileName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (fileSize != null)
                  Text(
                    _formatFileSize(fileSize),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const Icon(
              Icons.cloud_download,
              color: Colors.grey,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}