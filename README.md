# Strazh

Кроссплатформенный мессенджер на Flutter.

## Лицензия и безопасность

Исходный код распространяется на условиях [GNU AGPL-3.0](LICENSE). Правила
внесения изменений описаны в [CONTRIBUTING.md](CONTRIBUTING.md), а способ
сообщить об уязвимости — в [SECURITY.md](SECURITY.md).

Чаты работают как облачные чаты: сообщения хранятся на сервере и
синхронизируются между устройствами после входа в один аккаунт. Соединение с
Supabase должно использовать HTTPS, а доступ к сообщениям ограничивается
авторизацией и членством в комнате через RLS. Как и в обычных облачных чатах
Telegram, это **не сквозное шифрование**: сервер может обработать содержимое
сообщений. Не используйте эту модель, если требуется защита от самого
оператора сервера.

Новые сообщения сохраняются в облаке в открытом для сервера виде; название
столбца `encrypted_content` историческое и не означает, что данные зашифрованы
на устройстве. Старые сообщения, сохранённые предыдущей экспериментальной
E2E-версией, могут оставаться нечитаемыми. Миграция
`supabase/migrations/202611080002_cloud_chat_access.sql` удаляет таблицу
экспериментальных device-keys, ограничивает доступ к сообщениям и делает
вложения в `chat_media`, `chat_files` и `voice_messages` приватными. Вложения
доступны через короткоживущие ссылки только участникам соответствующего чата.
Примените её в Supabase перед выпуском. Уже развёрнутую старую push-функцию
нужно отдельно обновить.

## Структура проекта

- `lib/core/` — общие настройки, утилиты и инфраструктурные сервисы.
- `lib/features/` — модули приложения (`auth`, `chat`, `profile`, `settings`
  и другие); внутри каждого находятся `presentation/` и, где нужно, `data/`.
- `lib/shared/` — общие модели и виджеты, используемые разными модулями.
- `lib/main.dart` — точка входа приложения.
- `assets/` — локализации, изображения, шрифты, звуки и другие ресурсы.
- `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/` — платформенные
  проекты и настройки сборки.
- `supabase/` — миграции базы данных и Edge Functions.
- `server/` — серверные интеграции.
- `packages/` — локальные Dart/Flutter-пакеты.
- `test/` — автоматические тесты.
- `docs/` — инструкции и документация проекта.
- GitHub Actions запускает анализ и тесты для pull request и изменений в `main`.

## Разработка

```bash
flutter pub get
flutter analyze
flutter test
```

Инструкции по диагностике проблем TLS-сертификатов находятся в
[руководстве по сертификатам](docs/CERTIFICATE_TROUBLESHOOTING.md).

## Тестовое сообщение с кодом в чате «Коды входа»

В тестовом режиме приложение вызывает SQL RPC `request_phone_login_message`.
RPC создает запись, которая появляется в Realtime-чате аккаунта; SMS и письма
не отправляются. Код хранится в базе в открытом виде, но читать его может
только владелец аккаунта по RLS. Это предназначено только для тестирования:
для production замените этот RPC на серверную функцию с шифрованием и
проверкой кода. Код вводится на экране запроса и проверяется через SQL RPC с
лимитом в пять попыток. После проверки сервер запрашивает у Supabase Auth
одноразовый OTP, а приложение обменивает его на обычную Supabase-сессию и
открывает аккаунт. OTP не отправляется по почте: он передаётся приложению по
защищённому ответу Edge Function.

Примените в SQL Editor четыре миграции именно в таком порядке:
`202610260001_anonymous_phone_numbers.sql`,
`202610260002_phone_chat_login.sql`,
`202610270001_phone_login_chat_rpc.sql` и
`202610270002_phone_login_auth_session.sql`. Edge Function
`verify-phone-login` должна быть обновлена в Runtime; она не использует
сторонние npm-модули. Для self-hosted установки скопируйте её в
`/root/supabase/functions/verify-phone-login/index.ts`, затем обновите файл в
работающем контейнере `supabase_functions_root` по пути
`/home/deno/functions/verify-phone-login/index.ts`.

### Supabase Cloud

Для запроса сообщения достаточно SQL RPC. Чтобы код создавал сессию, примените
все миграции выше и разверните обновлённую функцию:
`supabase functions deploy verify-phone-login`.

### Self-hosted Supabase

Для тестовой доставки сообщения отдельная настройка self-hosted Edge Runtime
не требуется; достаточно применить миграции через SQL Editor. Для выпуска
сессии скопируйте обновлённый файл в серверный каталог и работающий контейнер
Edge Functions.

## Прямое хранение файлов в Timeweb S3

Flutter загружает файлы напрямую в закрытый Timeweb S3 bucket по короткоживущим
подписанным ссылкам. Supabase остаётся для аккаунтов, чатов и базы данных;
Supabase Storage API для новых загрузок и чтения файлов не используется. S3
Secret Access Key хранится только на API-сервере и никогда не встраивается в
приложение. Публичные аватары и обои отдаются через подписанный API proxy, а
вложения чатов, истории и поддержки — через временные ссылки с проверкой
участия пользователя.

### Настройка API

1. Создайте в Timeweb **приватный** S3 bucket. На присланном скриншоте bucket
   отмечен как публичный — для чатов такой режим небезопасен. Для S3 endpoint
   используется `https://s3.twcstorage.ru`, регион — `ru-1`; привязывать отдельный
   домен через CNAME не нужно.
2. Создайте ключ доступа S3 с правами чтения, записи и удаления объектов
   bucket-а. На сервере `api.strazh.chat` установите файлы
   `server/s3_storage_common.php`, `server/s3_storage_signing.php` и
   `server/s3_public_asset.php` в web-каталог API. Нужны PHP 8+ и расширение
   cURL.
3. Задайте перечисленные переменные в защищённом окружении PHP/FPM веб-сервера,
   а не в Flutter, Git или публичном `.env`:

   ```dotenv
   SUPABASE_URL=https://auth.strazh.chat
   SUPABASE_ANON_KEY=<publishable key приложения>
   S3_ENDPOINT=https://s3.twcstorage.ru
   S3_REGION=ru-1
   S3_BUCKET=<имя приватного S3 bucket из панели Timeweb>
   S3_ACCESS_KEY_ID=<S3 Access Key>
   S3_SECRET_ACCESS_KEY=<S3 Secret Access Key>
   S3_PUBLIC_URL_SECRET=<случайный секрет не менее 32 байт>
   S3_PUBLIC_URL_BASE=https://api.strazh.chat/s3_public_asset.php
   S3_ALLOWED_ORIGINS=https://strazh.chat,https://www.strazh.chat
   ```

   Создайте `S3_PUBLIC_URL_SECRET` командой `openssl rand -hex 32`. Не
   присылайте S3-ключи в чат. Endpoint подписания проверяет пользовательскую
   Supabase-сессию и доступ к комнате/тикету через RLS; service-role ключ в
   приложении или S3 API для работы приложения не нужен.
4. В CORS настройках S3 bucket разрешите origin веб-приложения
   (`https://strazh.chat` и `https://www.strazh.chat`), методы `GET`, `PUT`,
   `DELETE`, `HEAD` и заголовок `Content-Type`. Если у веб-клиента другой
   origin, добавьте его в обе настройки `S3_ALLOWED_ORIGINS` и CORS bucket-а.

### Перенос существующих файлов и запуск приложения

Переносчик потоково копирует объекты из Supabase Storage в приватный S3 bucket
по ключам `<storage-bucket>/<object-path>`, обновляет публичные ссылки на
аватары/обложки и переводит ссылки на фото историй и вложения чатов в ключи
объектов. Исходные объекты он не удаляет:

```sh
npm --prefix tools/storage-migration ci

export SUPABASE_URL='https://auth.strazh.chat'
export SUPABASE_SERVICE_ROLE_KEY='<service_role только в локальном терминале>'
export S3_ENDPOINT='https://s3.twcstorage.ru'
export S3_REGION='ru-1'
export S3_BUCKET='<имя приватного S3 bucket>'
export S3_ACCESS_KEY_ID='<S3 Access Key>'
export S3_SECRET_ACCESS_KEY='<S3 Secret Access Key>'
export S3_PUBLIC_URL_SECRET='<тот же секрет, что задан на API-сервере>'
export S3_PUBLIC_URL_BASE='https://api.strazh.chat/s3_public_asset.php'
npm --prefix tools/storage-migration run migrate
```

Сначала загрузите PHP endpoint-ы на API и настройте их переменные окружения,
затем запустите перенос, соберите и выпустите новую версию приложения. На
время переноса остановите загрузки старой версией приложения; если она ещё
загружала файлы в Supabase Storage, запустите перенос повторно после обновления
клиентов. Проверьте фото, голосовые, документы, истории и вложения поддержки.
Мигратор намеренно не удаляет исходные объекты: до их отдельного удаления они
продолжают занимать место на сервере. Удаляйте их только после успешной
проверки приложения и копий в S3.

## Push-уведомления о сообщениях

Для доставки уведомлений при закрытом приложении нужен серверный отправитель:
Supabase Edge Function отправляет Firebase Cloud Messaging уведомление после
добавления сообщения в `public.messages`. В актуальном исходнике push содержит
только идентификатор чата для навигации и нейтральный текст «Новое сообщение»;
текст, имя отправителя и аватары не отправляются Firebase или Apple Push
Notification service. Идентификатор чата всё ещё раскрывает метаданные.
Обновите уже развёрнутую Edge Function, прежде чем полагаться на это поведение.

### Если используется Supabase Cloud

1. Привяжите каталог к проекту и примените миграцию:
   `supabase link --project-ref <project-ref>` и `supabase db push`.
2. Разверните функцию:
   `supabase functions deploy send-message-push`.
3. Создайте вне репозитория файл секретов Edge Function и задайте в нем:
   - `FIREBASE_SERVICE_ACCOUNT` — JSON сервисного аккаунта Firebase с
     разрешением отправлять FCM-сообщения;
   - `PUSH_WEBHOOK_SECRET` — случайный секрет для проверки webhook.
   Загрузите значения командой
   `supabase secrets set --env-file /путь/к/защищенному/fcm.env`.
   Не добавляйте файл секретов в репозиторий и не отправляйте его в чат.
4. В Supabase Dashboard создайте Database Webhook для таблицы
   `public.messages`, события `INSERT`, HTTP-метод `POST` и URL
   `https://<project-ref>.supabase.co/functions/v1/send-message-push`.
   Добавьте заголовок `x-push-webhook-secret` с тем же значением, что и
   `PUSH_WEBHOOK_SECRET`.
5. В Firebase включите Firebase Cloud Messaging API и настройте APNs
   authentication key и capability Push Notifications для iOS-приложения.
   На устройстве разрешите уведомления; настройка также доступна в приложении.

### Если Supabase установлен на вашем сервере

`supabase link`, `functions deploy` и адрес `*.supabase.co` здесь не нужны:
у self-hosted установки нет Management API. В стандартной Docker-установке
Edge Functions уже поддерживаются.

1. Примените миграцию `supabase/migrations/202610240005_user_devices.sql`
   через SQL Editor в Studio или `psql`, подключенный к базе на сервере.
2. Скопируйте каталог
   `supabase/functions/send-message-push` в
   `<каталог self-hosted Supabase>/volumes/functions/send-message-push`.
   Если репозиторий не находится на сервере, например:
   `scp -r supabase/functions/send-message-push user@<сервер>:<каталог-Supabase>/volumes/functions/`.
3. В каталоге установки Supabase создайте не попадающий в Git файл
   `.env.functions` с переменными `FIREBASE_SERVICE_ACCOUNT`,
   `PUSH_WEBHOOK_SECRET`. Подключите его к
   сервису `functions` в `docker-compose.yml` через `env_file`, например:
   `env_file: [.env.functions]`. Значения секретов те же, что описаны выше
   для Cloud; секрет Firebase не публикуйте.
   В стандартной self-hosted конфигурации `SUPABASE_URL` и
   `SUPABASE_SERVICE_ROLE_KEY` уже передаются в функцию. Если в вашей
   конфигурации их нет, задайте их для `functions` в `docker-compose.yml`;
   `SUPABASE_URL` должен указывать на внутренний API gateway, например
   `http://api-gw:8000`.
4. Для этого webhook отключите встроенную JWT-проверку Edge Functions в
   серверном `.env`: `FUNCTIONS_VERIFY_JWT=false`. Эта функция сама проверяет
   заголовок `x-push-webhook-secret`, поэтому не оставляйте этот endpoint без
   секрета. Если настройка изменилась, пересоздайте контейнеры, затем
   перезапустите функцию: `sh run.sh recreate functions` и
   `sh run.sh restart functions`.
5. В базе включите `pg_net` и создайте триггер. Замените URL на внутренний
   адрес gateway, доступный из контейнера Postgres, и задайте собственный
   случайный секрет вместо `<секрет>`. Функция URL должна оканчиваться на
   `/functions/v1/send-message-push`. Заголовок с секретом временно хранится в
   очереди `pg_net`; ограничьте доступ к базе и не выдавайте обычным
   пользователям права чтения схемы `net`.

   ```sql
   create extension if not exists pg_net with schema extensions;

   select vault.create_secret(
     'http://api-gw:8000/functions/v1/send-message-push',
     'push_function_url'
   );
   select vault.create_secret('<секрет>', 'push_webhook_secret');

   create or replace function public.notify_new_message_push()
   returns trigger
   language plpgsql
   security definer
   set search_path = ''
   as $$
   begin
     perform net.http_post(
       url := (
         select decrypted_secret
         from vault.decrypted_secrets
         where name = 'push_function_url'
       ),
       headers := jsonb_build_object(
         'Content-Type', 'application/json',
         'x-push-webhook-secret', (
           select decrypted_secret
           from vault.decrypted_secrets
           where name = 'push_webhook_secret'
         )
       ),
       body := jsonb_build_object(
         'type', tg_op,
         'table', tg_table_name,
         'schema', tg_table_schema,
         'record', to_jsonb(new),
         'old_record', null
       ),
       timeout_milliseconds := 5000
     );
     return new;
   end;
   $$;

   drop trigger if exists send_message_push on public.messages;
   create trigger send_message_push
   after insert on public.messages
   for each row execute function public.notify_new_message_push();
   ```

6. Перезапустите сервис `functions`, чтобы он загрузил код. После изменения
   `.env.functions` именно пересоздайте контейнер командой
   `sh run.sh recreate functions`. Если ваш сервер установлен не официальным
   Docker Compose способом, способ развертывания Edge Function и адрес gateway
   зависят от этой установки; триггер должен обращаться к URL, достижимому из
   Postgres, а не к `localhost` на вашем компьютере.

#### Обновление функции приватных уведомлений

После обновления исходник Edge Function нужно развернуть заново. Для стандартной
Docker установки с путем `/srv/supabase` это можно сделать командами из корня
репозитория:

```sh
scp supabase/functions/send-message-push/index.ts \
  user@<сервер>:/srv/supabase/volumes/functions/send-message-push/index.ts
ssh user@<сервер> 'cd /srv/supabase && sh run.sh restart functions'
```

Замените пользователя, сервер и путь на свои. Если каталог функции ещё не
создан, сначала создайте на сервере
`/srv/supabase/volumes/functions/send-message-push`.

Push-тело на Android и iOS нейтральное. Приложение использует полученный
`chatId`, чтобы открыть нужный чат после нажатия. Это сокращает раскрытие
содержимого, но не скрывает факт доставки уведомления и идентификатор чата от
провайдеров push.

Для Android обновите функцию на сервере и соберите/установите новую версию
приложения с плагином. Отдельная настройка Android-сервера для аватара не
требуется. Firebase Cloud Messaging и настройка APNs для iOS нужны в обоих
вариантах Supabase.
