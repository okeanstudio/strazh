# Диагностика и решение ошибки CERTIFICATE_VERIFY_FAILED

## Проблема
При загрузке аватарки или других файлов через Supabase Storage получается ошибка:
```
HandshakeException: Handshake error in client (OS Error:
CERTIFICATE_VERIFY_FAILED: application verification failure)
```

## Возможные причины

1. **Самоподписанный сертификат** - сертификат не подписан доверенным центром сертификации
2. **Неполная цепочка сертификатов** - промежуточные сертификаты не установлены на сервере
3. **Проблема с доменом** - имя в сертификате не совпадает с доменом
4. **Проблема с датой/временем** - время на устройстве неверно установлено
5. **Неверная версия TLS** - сервер использует старую версию TLS

## Решения

### 1. Проверка сертификата сервера

Используйте команду для проверки сертификата:

```bash
# Для домена auth.strazh.chat
openssl s_client -connect auth.strazh.chat:443 -showcerts

# Для Storage домена
openssl s_client -connect storage.auth.strazh.chat:443 -showcerts
```

Проверьте:
- ✅ Сертификат подписан доверенным центром (Subject: CN=...)
- ✅ Цепочка сертификатов полная (должно быть несколько сертификатов)
- ✅ Дата действия правильная (Not Before и Not After)
- ✅ Subject Alternative Names содержат нужные домены

### 2. Если сервер использует самоподписанный сертификат

Установите сертификат на iOS:

```
1. Экспортируйте сертификат сервера в формате .pem
2. Добавьте его в проект в папке ios/Certificates/
3. Обновите Info.plist чтобы доверить сертификату
```

### 3. Проверка на iOS Simulator

На iOS Simulator часто нужна особая конфигурация:

1. Убедитесь что часы на Simulator установлены правильно
2. Перестартуйте Simulator
3. Очистите кэш приложения

### 4. Проверка на реальном устройстве iOS

```bash
# На реальном iPhone/iPad
# Settings > General > Date & Time > Set Automatically (включить)
# Settings > General > VPN & Device Management (проверить сертификаты)
```

### 5. Проверка конфигурации Android

Файл `android/app/src/main/res/xml/network_security_config.xml` должен содержать:

```xml
<domain includeSubdomains="true">auth.strazh.chat</domain>
```

### 6. Если сервер Supabase работает на нестандартном домене

Если Supabase работает на домене отличном от стандартного supabase.co, добавьте его в Info.plist:

```xml
<dict>
    <key>your-custom-domain.com</key>
    <dict>
        <key>NSIncludesSubdomains</key>
        <true/>
        <key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
        <false/>
        <key>NSTemporaryExceptionMinimumTLSVersion</key>
        <string>TLSv1.2</string>
        <key>NSExceptionRequiresForwardSecrecy</key>
        <false/>
    </dict>
</dict>
```

## Логирование для диагностики

Чтобы получить более подробные логи при разработке, используйте:

```dart
// В main.dart добавьте перед Supabase.initialize()
if (kDebugMode) {
  // Включить детальное логирование
}
```

## Временное решение для разработки (⚠️ ТОЛЬКО ДЛЯ DEBUG)

**Внимание: Это небезопасно в production!**

Если вы уверены в источнике и разрабатываете локально, можно временно отключить проверку:

```dart
// ТОЛЬКО В DEBUG РЕЖИМЕ
httpClient.badCertificateCallback = (cert, host, port) {
  return host == 'your-development-server.local';
};
```

## Рекомендации

- ✅ Используйте сертификаты от доверенных ЦС (Let's Encrypt, DigiCert и т.д.)
- ✅ Убедитесь что цепочка сертификатов полная
- ✅ Регулярно обновляйте сертификаты перед истечением
- ✅ Используйте минимум TLSv1.2
- ✅ Проверяйте что часы на устройствах установлены правильно
- ✅ На production никогда не отключайте проверку сертификатов

## Контактная информация

Если проблема не решается:
1. Проверьте логи из консоли Flutter: `flutter run -v`
2. Используйте `openssl` для диагностики сертификата
3. Проверьте что домен в сертификате совпадает с используемым доменом
