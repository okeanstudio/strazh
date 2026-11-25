# Web: аватары и CORS изображений

Веб-клиент загружает публичные аватары через
`https://api.strazh.chat/s3_public_asset.php`. Endpoint возвращает redirect на
Timeweb S3, поэтому браузер должен получить CORS-разрешение и от API, и от S3.

## API-сервер

Загрузите обновлённый `server/s3_public_asset.php` в API web-каталог. В
окружении PHP-FPM сохраните текущие разрешённые origins и добавьте
`https://web.strazh.chat`, например:

```dotenv
S3_ALLOWED_ORIGINS=https://strazh.chat,https://www.strazh.chat,https://web.strazh.chat
```

Endpoint разрешает `https://web.strazh.chat` по умолчанию, если переменная не
задана. Если `S3_ALLOWED_ORIGINS` уже задана, добавьте origin к существующему
списку, не удаляя другие клиенты. Перезапустите PHP-FPM после обновления
переменных окружения.

## Timeweb S3 bucket

В настройках CORS bucket-а разрешите origin `https://web.strazh.chat` с
методами `GET` и `HEAD`. Если веб-приложение также загружает файлы напрямую,
оставьте используемые им `PUT` и заголовок `Content-Type`. Сохраните прочие
origin-ы, которые уже нужны мобильным или другим веб-клиентам.

## Content Security Policy

Если сайт задаёт CSP, проверьте, что его `img-src` разрешает API endpoint и
S3 endpoint:

```text
img-src 'self' data: blob: https://api.strazh.chat https://s3.twcstorage.ru;
```

Добавьте эти источники в существующую политику, не создавая второй
конфликтующий `Content-Security-Policy` header.

В Safari очистите данные сайта или откройте приложение в приватном окне после
обновления конфигурации. В Web Inspector проверьте запрос аватара: успешный
ответ должен пройти redirect с API на S3 и завершиться кодом `200`.
