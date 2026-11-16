<?php

function s3_storage_respond($status, $payload)
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit();
}

function s3_storage_env($name, $default = '')
{
    $value = getenv($name);
    return $value === false ? $default : trim((string) $value);
}

function s3_storage_config()
{
    $config = [
        'supabase_url' => rtrim(
            s3_storage_env('SUPABASE_URL', 'https://auth.strazh.chat'),
            '/'
        ),
        'supabase_anon_key' => s3_storage_env('SUPABASE_ANON_KEY'),
        'endpoint' => rtrim(s3_storage_env('S3_ENDPOINT'), '/'),
        'region' => s3_storage_env('S3_REGION', 'ru-1'),
        'bucket' => s3_storage_env('S3_BUCKET'),
        'access_key' => s3_storage_env('S3_ACCESS_KEY_ID'),
        'secret_key' => s3_storage_env('S3_SECRET_ACCESS_KEY'),
        'public_url_secret' => s3_storage_env('S3_PUBLIC_URL_SECRET'),
        'public_url_base' => rtrim(
            s3_storage_env(
                'S3_PUBLIC_URL_BASE',
                'https://api.strazh.chat/s3_public_asset.php'
            ),
            '/'
        ),
    ];

    foreach (
        ['supabase_anon_key', 'endpoint', 'region', 'bucket', 'access_key',
        'secret_key', 'public_url_secret'] as $name
    ) {
        if ($config[$name] === '') {
            error_log('S3 storage is not configured: ' . $name);
            s3_storage_respond(503, ['message' => 'S3-хранилище не настроено']);
        }
    }

    $endpoint = parse_url($config['endpoint']);
    if (
        !is_array($endpoint) ||
        ($endpoint['scheme'] ?? '') !== 'https' ||
        empty($endpoint['host']) ||
        isset($endpoint['path']) && $endpoint['path'] !== '' ||
        isset($endpoint['query']) ||
        isset($endpoint['fragment'])
    ) {
        error_log('S3 storage endpoint must be a root HTTPS URL');
        s3_storage_respond(500, ['message' => 'Неверно настроен S3 endpoint']);
    }

    return $config;
}

function s3_storage_cors()
{
    $origin = $_SERVER['HTTP_ORIGIN'] ?? '';
    $allowed = array_filter(array_map(
        'trim',
        explode(',', s3_storage_env(
            'S3_ALLOWED_ORIGINS',
            'https://strazh.chat,https://www.strazh.chat,http://localhost:3000,http://localhost:5000'
        ))
    ));

    if ($origin !== '' && in_array($origin, $allowed, true)) {
        header('Access-Control-Allow-Origin: ' . $origin);
        header('Vary: Origin');
    }
    header('Access-Control-Allow-Methods: POST, OPTIONS');
    header('Access-Control-Allow-Headers: Authorization, Content-Type');
    header('Access-Control-Max-Age: 600');

    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
        http_response_code(204);
        exit();
    }
}

function s3_storage_http_request($url, $method, $headers, $body = null)
{
    $curl = curl_init($url);
    if ($curl === false) {
        s3_storage_respond(502, ['message' => 'Не удалось подключиться к сервису']);
    }

    curl_setopt_array($curl, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 8,
        CURLOPT_TIMEOUT => 20,
        CURLOPT_HTTPHEADER => $headers,
    ]);
    if ($body !== null) {
        curl_setopt($curl, CURLOPT_POSTFIELDS, $body);
    }

    $response = curl_exec($curl);
    $status = (int) curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $error = curl_error($curl);
    curl_close($curl);
    if ($response === false) {
        error_log('S3 storage upstream request failed: ' . $error);
        s3_storage_respond(502, ['message' => 'Сервис временно недоступен']);
    }

    return [
        'status' => $status,
        'data' => json_decode($response, true),
    ];
}

function s3_storage_bearer_token()
{
    $header = $_SERVER['HTTP_AUTHORIZATION'] ?? '';
    if (!preg_match('/^Bearer\s+([^\s]+)$/i', $header, $matches)) {
        s3_storage_respond(401, ['message' => 'Необходим вход в аккаунт']);
    }
    return $matches[1];
}

function s3_storage_authenticated_user($config, $token)
{
    $result = s3_storage_http_request(
        $config['supabase_url'] . '/auth/v1/user',
        'GET',
        [
            'apikey: ' . $config['supabase_anon_key'],
            'Authorization: Bearer ' . $token,
        ]
    );
    if (
        $result['status'] !== 200 ||
        !is_array($result['data']) ||
        empty($result['data']['id'])
    ) {
        s3_storage_respond(401, ['message' => 'Сессия истекла. Войдите заново.']);
    }
    return $result['data'];
}

function s3_storage_query_as_user($config, $token, $table, $query)
{
    return s3_storage_http_request(
        $config['supabase_url'] . '/rest/v1/' . $table . '?' . $query,
        'GET',
        [
            'apikey: ' . $config['supabase_anon_key'],
            'Authorization: Bearer ' . $token,
            'Accept: application/json',
        ]
    );
}

function s3_storage_bucket_is_public($bucket)
{
    return in_array(
        $bucket,
        ['avatars', 'channel_avatars', 'group_avatars', 'chat_wallpapers'],
        true
    );
}

function s3_storage_validate_path($path)
{
    if (
        $path === '' ||
        strlen($path) > 1024 ||
        $path[0] === '/' ||
        strpos($path, '\\') !== false ||
        preg_match('/[\x00-\x1F\x7F]/', $path)
    ) {
        s3_storage_respond(400, ['message' => 'Некорректный путь файла']);
    }

    foreach (explode('/', $path) as $segment) {
        if ($segment === '' || $segment === '.' || $segment === '..') {
            s3_storage_respond(400, ['message' => 'Некорректный путь файла']);
        }
    }
}

function s3_storage_is_uuid($value)
{
    return is_string($value) && preg_match(
        '/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i',
        $value
    ) === 1;
}

function s3_storage_require_visible_row(
    $config,
    $token,
    $table,
    $query,
    $message = 'Файл недоступен'
) {
    $result = s3_storage_query_as_user($config, $token, $table, $query);
    if (
        $result['status'] < 200 ||
        $result['status'] >= 300 ||
        !is_array($result['data']) ||
        count($result['data']) === 0
    ) {
        s3_storage_respond(403, ['message' => $message]);
    }
}

function s3_storage_authorize(
    $config,
    $token,
    $user,
    $bucket,
    $path,
    $action
) {
    $segments = explode('/', $path);
    $userId = (string) $user['id'];
    $first = $segments[0];
    $isWrite = $action === 'upload' || $action === 'delete';

    if (s3_storage_bucket_is_public($bucket)) {
        if (!$isWrite) {
            return;
        }
        if (!s3_storage_is_uuid($first) || $first !== $userId) {
            s3_storage_respond(403, ['message' => 'Нет доступа к этому файлу']);
        }
        return;
    }

    if (in_array($bucket, ['chat_media', 'chat_files', 'voice_messages'], true)) {
        if (!s3_storage_is_uuid($first)) {
            s3_storage_respond(400, ['message' => 'Некорректный путь вложения']);
        }
        $membership = s3_storage_query_as_user(
            $config,
            $token,
            'room_participants',
            'select=room_id&room_id=eq.' . rawurlencode($first) .
                '&user_id=eq.' . rawurlencode($userId) . '&limit=1'
        );
        if (
            $membership['status'] >= 200 &&
            $membership['status'] < 300 &&
            is_array($membership['data']) &&
            count($membership['data']) > 0
        ) {
            return;
        }
        if ($isWrite) {
            s3_storage_respond(403, ['message' => 'Нет доступа к этому чату']);
        }

        $pathFilter = static function ($column) use ($path) {
            return $column . '.eq.' . rawurlencode($path);
        };
        $publicChannel = s3_storage_query_as_user(
            $config,
            $token,
            'messages',
            'select=id,rooms!inner(id)' .
                '&room_id=eq.' . rawurlencode($first) .
                '&or=(' . $pathFilter('file_url') . ',' .
                $pathFilter('voice_url') . ',' .
                $pathFilter('encrypted_content') . ')' .
                '&rooms.type=eq.channel&rooms.is_private=eq.false&limit=1'
        );
        if (
            $publicChannel['status'] >= 200 &&
            $publicChannel['status'] < 300 &&
            is_array($publicChannel['data']) &&
            count($publicChannel['data']) > 0
        ) {
            return;
        }
        s3_storage_respond(403, ['message' => 'Файл недоступен']);
    }

    if ($bucket === 'support-ticket-attachments') {
        if (!s3_storage_is_uuid($first)) {
            s3_storage_respond(400, ['message' => 'Некорректный путь вложения']);
        }
        s3_storage_require_visible_row(
            $config,
            $token,
            'support_tickets',
            'select=id&id=eq.' . rawurlencode($first) . '&limit=1'
        );
        if ($isWrite) {
            $ticket = s3_storage_query_as_user(
                $config,
                $token,
                'support_tickets',
                'select=status&id=eq.' . rawurlencode($first) . '&limit=1'
            );
            $status = $ticket['data'][0]['status'] ?? '';
            if ($status === 'closed') {
                s3_storage_respond(403, ['message' => 'Обращение уже закрыто']);
            }
        }
        return;
    }

    if ($bucket === 'stories') {
        if ($isWrite) {
            if (!s3_storage_is_uuid($first) || $first !== $userId) {
                s3_storage_respond(403, ['message' => 'Нет доступа к этой истории']);
            }
            $metadata = $user['user_metadata'] ?? [];
            $subscriptionType = strtolower(trim(
                (string) ($metadata['subscription_type'] ?? '')
            ));
            $planId = strtolower(trim(
                (string) ($metadata['subscription_plan_id'] ?? '')
            ));
            $expiresAt = strtolower(trim((string) ($metadata['subscription_expires_at'] ?? '')));
            if (
                ($subscriptionType !== 'premium' && $planId !== 'forever') ||
                ($expiresAt !== 'forever' && $planId !== 'forever' &&
                    ($expiresAt === '' || strtotime($expiresAt) <= time()))
            ) {
                s3_storage_respond(403, ['message' => 'Для публикации истории нужна активная подписка']);
            }
            return;
        }

        s3_storage_require_visible_row(
            $config,
            $token,
            'stories',
            'select=id&image_url=eq.' . rawurlencode($path)
        );
        return;
    }

    s3_storage_respond(400, ['message' => 'Неизвестный тип файла']);
}

function s3_storage_encode_segment($segment)
{
    return str_replace('%7E', '~', rawurlencode($segment));
}

function s3_storage_presign($config, $method, $objectKey, $expiresIn)
{
    $endpoint = parse_url($config['endpoint']);
    $host = $endpoint['host'];
    if (isset($endpoint['port'])) {
        $host .= ':' . $endpoint['port'];
    }
    $path = $config['bucket'] . '/' . $objectKey;
    $canonicalUri = '/' . implode(
        '/',
        array_map('s3_storage_encode_segment', explode('/', $path))
    );
    $timestamp = gmdate('Ymd\THis\Z');
    $date = gmdate('Ymd');
    $scope = $date . '/' . $config['region'] . '/s3/aws4_request';

    $query = [
        'X-Amz-Algorithm' => 'AWS4-HMAC-SHA256',
        'X-Amz-Credential' => $config['access_key'] . '/' . $scope,
        'X-Amz-Date' => $timestamp,
        'X-Amz-Expires' => (string) $expiresIn,
        'X-Amz-SignedHeaders' => 'host',
    ];
    ksort($query, SORT_STRING);
    $canonicalQuery = [];
    foreach ($query as $name => $value) {
        $canonicalQuery[] = s3_storage_encode_segment($name) . '=' .
            s3_storage_encode_segment($value);
    }
    $canonicalQueryString = implode('&', $canonicalQuery);
    $canonicalRequest = $method . "\n" . $canonicalUri . "\n" .
        $canonicalQueryString . "\n" . 'host:' . $host . "\n\nhost\n" .
        'UNSIGNED-PAYLOAD';
    $stringToSign = "AWS4-HMAC-SHA256\n" . $timestamp . "\n" . $scope .
        "\n" . hash('sha256', $canonicalRequest);

    $dateKey = hash_hmac('sha256', $date, 'AWS4' . $config['secret_key'], true);
    $regionKey = hash_hmac('sha256', $config['region'], $dateKey, true);
    $serviceKey = hash_hmac('sha256', 's3', $regionKey, true);
    $signingKey = hash_hmac('sha256', 'aws4_request', $serviceKey, true);
    $signature = hash_hmac('sha256', $stringToSign, $signingKey);

    return $config['endpoint'] . $canonicalUri . '?' .
        $canonicalQueryString . '&X-Amz-Signature=' . $signature;
}

function s3_storage_public_url($config, $bucket, $path)
{
    $signature = hash_hmac(
        'sha256',
        $bucket . "\n" . $path,
        $config['public_url_secret']
    );
    return $config['public_url_base'] . '?' . http_build_query(
        ['bucket' => $bucket, 'path' => $path, 'signature' => $signature],
        '',
        '&',
        PHP_QUERY_RFC3986
    );
}
