import 'package:flutter/material.dart';

class UserStatusService {
  static String getStatusText(String? status) {
    switch (status) {
      case 'online':
        return 'В сети';
      case 'away':
        return 'Отошёл';
      case 'busy':
        return 'Занят';
      default:
        return 'Не в сети';
    }
  }

  static Color getStatusColor(String? status) {
    switch (status) {
      case 'online':
        return Colors.green;
      case 'away':
        return Colors.orange;
      case 'busy':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  static String normalizeStatus(String? status) {
    if (status == null || status.trim().isEmpty) {
      return 'offline';
    }
    return status;
  }
}
