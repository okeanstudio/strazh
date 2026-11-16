class AppConfig {
  // Supabase
  static const String supabaseUrl = 'https://auth.strazh.chat';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNzkzMzg2NjA3LCJleHAiOjIxMDg3NDY2MDd9.e7XFupMlqJZ7wHTSi7pDTE2byDGQafOaJyhvfBeuO_g';

  // Твой API
  static const String apiBaseUrl = 'https://api.strazh.chat';
  static const String appUrl = 'https://strazh.chat';

  // Endpoints
  static const String sendVerification = '$apiBaseUrl/send_verification.php';
  static const String verifyCode = '$apiBaseUrl/verify_code.php';
  static const String s3StorageSigning = '$apiBaseUrl/s3_storage_signing.php';
  static const String s3PublicAsset = '$apiBaseUrl/s3_public_asset.php';
}
