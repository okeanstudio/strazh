# Web Push для Strazh

Web Push на iPhone работает в iOS/iPadOS 16.4 и новее, только если пользователь
добавил сайт на экран «Домой» и открыл установленное веб-приложение. Apple
Developer аккаунт и сертификат разработчика не требуются.

Перед публикацией веб-клиента:

1. В проекте Firebase `strazh-e2ee` зарегистрировать Web App и скопировать
   публичные параметры Firebase Web App в `web/firebase-messaging-config.json`.
2. В Firebase Console → Project settings → Cloud Messaging создать Web Push
   certificate key pair и записать публичный VAPID key в `vapidKey` того же
   JSON-файла. Не добавлять сюда service-account private key.
3. Развернуть сайт по HTTPS вместе с `firebase-messaging-sw.js` и
   `firebase-messaging-config.json` в корне сайта.
4. Развернуть обновлённую Supabase Edge Function `send-message-push`.
5. На iPhone открыть сайт в Safari, выбрать «Поделиться» → «На экран Домой»,
   запустить Strazh с иконки и разрешить уведомления.

Веб-токены сохраняются в `user_devices` с `platform = 'web'`; отправка
использует существующий Firebase service account на сервере.
