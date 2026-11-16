<?php

require_once __DIR__ . '/s3_storage_common.php';

s3_storage_cors();
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    s3_storage_respond(405, ['message' => 'Используйте POST']);
}

$input = json_decode((string) file_get_contents('php://input'), true);
if (!is_array($input)) {
    s3_storage_respond(400, ['message' => 'Некорректный JSON']);
}

$action = (string) ($input['action'] ?? '');
$bucket = (string) ($input['bucket'] ?? '');
$path = (string) ($input['path'] ?? '');
$supportedBuckets = [
    'avatars',
    'channel_avatars',
    'group_avatars',
    'chat_wallpapers',
    'chat_media',
    'chat_files',
    'voice_messages',
    'stories',
    'support-ticket-attachments',
];
if (!in_array($bucket, $supportedBuckets, true)) {
    s3_storage_respond(400, ['message' => 'Неизвестный тип файла']);
}
s3_storage_validate_path($path);

$config = s3_storage_config();
$token = s3_storage_bearer_token();
$user = s3_storage_authenticated_user($config, $token);

if ($action === 'public_url') {
    if (!s3_storage_bucket_is_public($bucket)) {
        s3_storage_respond(403, ['message' => 'Для этого файла нет публичной ссылки']);
    }
    s3_storage_authorize($config, $token, $user, $bucket, $path, $action);
    s3_storage_respond(200, [
        'url' => s3_storage_public_url($config, $bucket, $path),
    ]);
}

if (!in_array($action, ['upload', 'read', 'delete'], true)) {
    s3_storage_respond(400, ['message' => 'Неизвестное действие']);
}
s3_storage_authorize($config, $token, $user, $bucket, $path, $action);

$method = [
    'upload' => 'PUT',
    'read' => 'GET',
    'delete' => 'DELETE',
][$action];
$expiresIn = $action === 'upload'
    ? 900
    : max(60, min((int) ($input['expires_in'] ?? 3600), 3600));

s3_storage_respond(200, [
    'url' => s3_storage_presign(
        $config,
        $method,
        $bucket . '/' . $path,
        $expiresIn
    ),
]);
