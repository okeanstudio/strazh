import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:strazh/features/auth/data/services/auth_service.dart';
import 'package:strazh/features/chat/data/services/crypto_service.dart';
import 'package:strazh/core/utils/rpc_user.dart';
import 'package:strazh/features/chat/data/services/storage_upload_service.dart';

class SupportTicketService {
  static const String _attachmentBucket = 'support-ticket-attachments';
  static const int maxAttachmentSize = 15 * 1024 * 1024;

  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();
  final CryptoService _crypto = CryptoService();

  Future<List<Map<String, dynamic>>> getMyTickets() async {
    final userId = _authService.currentUserId;
    if (userId == null) return [];

    final rows = await _supabase
        .from('support_tickets')
        .select(
          'id, user_id, category, subject, status, created_at, updated_at',
        )
        .eq('user_id', userId)
        .order('updated_at', ascending: false);

    return rows.map(_decodeTicket).toList();
  }

  Future<List<Map<String, dynamic>>> getAllTickets() async {
    final rows = await _supabase
        .from('support_tickets')
        .select(
          'id, user_id, category, subject, status, created_at, updated_at',
        )
        .order('updated_at', ascending: false);

    final tickets = <Map<String, dynamic>>[];
    for (final row in rows) {
      final ticket = _decodeTicket(row);
      try {
        final response = await _supabase.rpc(
          'get_user_by_id',
          params: {'p_id': row['user_id']},
        );
        final user = rpcUserRecord(response);
        ticket['user_name'] = user?['name'] ?? 'Пользователь';
        ticket['user_tag'] = user?['tag'] ?? '';
      } catch (error) {
        debugPrint('Не удалось получить автора тикета: $error');
        ticket['user_name'] = 'Пользователь';
        ticket['user_tag'] = '';
      }
      tickets.add(ticket);
    }
    return tickets;
  }

  Future<List<Map<String, dynamic>>> getMessages(String ticketId) async {
    final rows = await _supabase
        .from('support_ticket_messages')
        .select(
          'id, ticket_id, sender_id, sender_type, body, created_at, attachment_path, attachment_name, attachment_mime_type, attachment_size',
        )
        .eq('ticket_id', ticketId)
        .order('created_at');

    final messages = <Map<String, dynamic>>[];
    for (final row in rows) {
      final message = Map<String, dynamic>.from(row);
      message['body'] = _decrypt(row['body'] as String? ?? '');
      final attachmentPath = row['attachment_path'] as String?;
      if (attachmentPath != null) {
        message['attachment_name'] = _decrypt(
          row['attachment_name'] as String? ?? '',
        );
        try {
          message['attachment_url'] =
              await StorageUploadService.createSignedUrl(
                bucket: _attachmentBucket,
                path: attachmentPath,
                expiresIn: 3600,
              );
        } catch (error) {
          debugPrint('Не удалось создать ссылку на вложение: $error');
        }
      }
      messages.add(message);
    }
    return messages;
  }

  Future<Map<String, dynamic>> createTicket({
    required String category,
    required String subject,
    required String message,
    XFile? attachment,
  }) async {
    final userId = _authService.currentUserId;
    if (userId == null) throw StateError('Необходимо войти в аккаунт');

    final ticket = await _supabase
        .from('support_tickets')
        .insert({
          'user_id': userId,
          'category': category,
          'subject': _crypto.encodeCloudContent(subject.trim()),
        })
        .select(
          'id, user_id, category, subject, status, created_at, updated_at',
        )
        .single();

    await _insertMessage(
      ticketId: ticket['id'] as String,
      senderId: userId,
      senderType: 'user',
      body: message,
      attachment: attachment,
    );

    return _decodeTicket(ticket);
  }

  Future<void> sendReply({
    required String ticketId,
    required String body,
    required bool fromSupport,
    XFile? attachment,
  }) async {
    final userId = _authService.currentUserId;
    if (userId == null) throw StateError('Необходимо войти в аккаунт');

    await _insertMessage(
      ticketId: ticketId,
      senderId: userId,
      senderType: fromSupport ? 'support' : 'user',
      body: body,
      attachment: attachment,
    );
  }

  Future<void> closeOwnTicket(String ticketId) async {
    await _supabase
        .from('support_tickets')
        .update({
          'status': 'closed',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', ticketId);
  }

  Future<void> setTicketStatus(String ticketId, String status) async {
    await _supabase
        .from('support_tickets')
        .update({
          'status': status,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', ticketId);
  }

  Future<void> _insertMessage({
    required String ticketId,
    required String senderId,
    required String senderType,
    required String body,
    XFile? attachment,
  }) async {
    Map<String, dynamic> attachmentData = {};
    if (attachment != null) {
      final bytes = await attachment.readAsBytes();
      if (bytes.length > maxAttachmentSize) {
        throw StateError('Размер файла превышает 15 МБ');
      }
      final safeName = attachment.name.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      final path =
          '$ticketId/${DateTime.now().microsecondsSinceEpoch}_$safeName';
      final mimeType = _mimeTypeFor(attachment);
      await StorageUploadService.uploadBinary(
        bucket: _attachmentBucket,
        path: path,
        bytes: bytes,
        contentType: mimeType,
        onProgress: (_, _) {},
      );
      attachmentData = {
        'attachment_path': path,
        'attachment_name': _crypto.encodeCloudContent(attachment.name),
        'attachment_mime_type': mimeType,
        'attachment_size': bytes.length,
      };
    }

    await _supabase.from('support_ticket_messages').insert({
      'ticket_id': ticketId,
      'sender_id': senderId,
      'sender_type': senderType,
      'body': _crypto.encodeCloudContent(body.trim()),
      ...attachmentData,
    });
  }

  Map<String, dynamic> _decodeTicket(Map<String, dynamic> row) {
    final ticket = Map<String, dynamic>.from(row);
    ticket['subject'] = _decrypt(row['subject'] as String? ?? '');
    return ticket;
  }

  String _decrypt(String value) {
    return _crypto.decodeCloudContent(value);
  }

  String _mimeTypeFor(XFile file) {
    final detectedType = file.mimeType?.trim();
    if (detectedType != null &&
        detectedType.isNotEmpty &&
        detectedType != 'application/octet-stream') {
      return detectedType;
    }

    switch (file.name.split('.').last.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'bmp':
        return 'image/bmp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}
