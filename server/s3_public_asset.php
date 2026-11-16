<?php

require_once __DIR__ . '/s3_storage_common.php';

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'GET') {
    http_response_code(405);
    exit();
}

$bucket = (string) ($_GET['bucket'] ?? '');
$path = (string) ($_GET['path'] ?? '');
$signature = (string) ($_GET['signature'] ?? '');
if (
    !s3_storage_bucket_is_public($bucket) ||
    $path === '' ||
    $signature === ''
) {
    http_response_code(404);
    exit();
}

try {
    s3_storage_validate_path($path);
    $config = s3_storage_config();
} catch (Throwable $error) {
    http_response_code(404);
    exit();
}

$expected = hash_hmac(
    'sha256',
    $bucket . "\n" . $path,
    $config['public_url_secret']
);
if (!hash_equals($expected, $signature)) {
    http_response_code(404);
    exit();
}

header('Cache-Control: public, max-age=300');
header('Location: ' . s3_storage_presign(
    $config,
    'GET',
    $bucket . '/' . $path,
    300
), true, 302);
exit();
