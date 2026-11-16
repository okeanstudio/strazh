<?php
/**
 * Strazh - последовательное подтверждение и смена email
 */

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(405, false, 'Метод не разрешен. Используйте POST.');
}

$input = json_decode((string) file_get_contents('php://input'), true);
if (!is_array($input)) {
    respond(400, false, 'Некорректный JSON');
}

$action = (string) ($input['action'] ?? '');
$accessToken = trim((string) ($input['access_token'] ?? ''));
if ($accessToken === '') {
    respond(401, false, 'Сессия истекла. Войдите в аккаунт повторно.');
}

$supabaseUrl = rtrim((string) (getenv('SUPABASE_URL') ?: 'https://auth.strazh.chat'), '/');
$supabaseAnonKey = (string) (
    getenv('SUPABASE_ANON_KEY') ?: 'sb_publishable_ACJWlzQHvfOxg_3BJgxAaH'
);
$serviceRoleKey = trim((string) getenv('SUPABASE_SERVICE_ROLE_KEY'));
if ($serviceRoleKey === '') {
    error_log('Email change endpoint: SUPABASE_SERVICE_ROLE_KEY is not configured');
    respond(500, false, 'На сервере смены email не настроен Supabase service role key');
}

$auth = request_json(
    $supabaseUrl . '/auth/v1/user',
    'GET',
    null,
    [
        'apikey: ' . $supabaseAnonKey,
        'Authorization: Bearer ' . $accessToken,
    ]
);
if ($auth['status'] !== 200 || !is_array($auth['data'])) {
    respond(401, false, 'Сессия недействительна. Войдите в аккаунт повторно.');
}

$userId = (string) ($auth['data']['id'] ?? '');
$oldEmail = strtolower(trim((string) ($auth['data']['email'] ?? '')));
if ($userId === '' || $oldEmail === '') {
    respond(401, false, 'Не удалось определить аккаунт и текущий email');
}

$tableUrl = $supabaseUrl . '/rest/v1/email_change_challenges';
$adminHeaders = [
    'apikey: ' . $serviceRoleKey,
    'Authorization: Bearer ' . $serviceRoleKey,
];

if ($action === 'start') {
    $newEmail = strtolower(trim((string) ($input['new_email'] ?? '')));
    if (!filter_var($newEmail, FILTER_VALIDATE_EMAIL)) {
        respond(400, false, 'Введите корректный новый email');
    }
    if ($newEmail === $oldEmail) {
        respond(400, false, 'Новый email совпадает с текущим');
    }

    $existing = load_challenge($tableUrl, $adminHeaders, $userId);
    if ($existing !== null) {
        $lastSent = strtotime((string) ($existing['last_sent_at'] ?? ''));
        if ($lastSent !== false && time() - $lastSent < 60) {
            respond(429, false, 'Повторно запросить код можно через минуту');
        }
    }

    $oldCode = create_code();
    send_email($oldEmail, $oldCode);
    save_challenge($tableUrl, $adminHeaders, $userId, [
        'old_email' => $oldEmail,
        'new_email' => $newEmail,
        'stage' => 'old',
        'old_code_hash' => code_hash($userId, $oldCode, $serviceRoleKey),
        'new_code_hash' => null,
        'attempts' => 0,
        'expires_at' => gmdate('c', time() + 600),
        'last_sent_at' => gmdate('c'),
    ]);
    respond(200, true, 'Код отправлен на текущий email');
}

if ($action !== 'verify_old' && $action !== 'verify_new') {
    respond(400, false, 'Неизвестное действие');
}

$challenge = load_challenge($tableUrl, $adminHeaders, $userId);
if ($challenge === null) {
    respond(400, false, 'Запрос на смену email не найден. Начните заново.');
}
if (strtolower((string) $challenge['old_email']) !== $oldEmail) {
    delete_challenge($tableUrl, $adminHeaders, $userId);
    respond(400, false, 'Текущий email изменился. Начните заново.');
}
if (strtotime((string) $challenge['expires_at']) < time()) {
    delete_challenge($tableUrl, $adminHeaders, $userId);
    respond(400, false, 'Срок действия кода истек. Начните заново.');
}
if ((int) $challenge['attempts'] >= 5) {
    delete_challenge($tableUrl, $adminHeaders, $userId);
    respond(429, false, 'Слишком много попыток. Начните смену email заново.');
}

$expectedStage = $action === 'verify_old' ? 'old' : 'new';
if ($challenge['stage'] !== $expectedStage) {
    respond(400, false, 'Неверный этап подтверждения');
}

$code = trim((string) ($input['code'] ?? ''));
if (!preg_match('/^\d{6}$/', $code)) {
    respond(400, false, 'Введите 6-значный код');
}
$hashColumn = $action === 'verify_old' ? 'old_code_hash' : 'new_code_hash';
$expectedHash = (string) ($challenge[$hashColumn] ?? '');
$providedHash = code_hash($userId, $code, $serviceRoleKey);
if ($expectedHash === '' || !hash_equals($expectedHash, $providedHash)) {
    update_challenge($tableUrl, $adminHeaders, $userId, [
        'attempts' => (int) $challenge['attempts'] + 1,
    ]);
    respond(400, false, 'Неверный код');
}

if ($action === 'verify_old') {
    $newCode = create_code();
    send_email((string) $challenge['new_email'], $newCode);
    update_challenge($tableUrl, $adminHeaders, $userId, [
        'stage' => 'new',
        'new_code_hash' => code_hash($userId, $newCode, $serviceRoleKey),
        'attempts' => 0,
        'last_sent_at' => gmdate('c'),
    ]);
    respond(200, true, 'Старый email подтвержден. Код отправлен на новый адрес.');
}

$updatedUser = request_json(
    $supabaseUrl . '/auth/v1/admin/users/' . rawurlencode($userId),
    'PUT',
    [
        'email' => (string) $challenge['new_email'],
        'email_confirm' => true,
    ],
    $adminHeaders
);
if ($updatedUser['status'] < 200 || $updatedUser['status'] >= 300) {
    if ($updatedUser['status'] === 409 || $updatedUser['status'] === 422) {
        delete_challenge($tableUrl, $adminHeaders, $userId);
        respond(409, false, 'Этот email уже используется другим аккаунтом');
    }
    error_log('Supabase email update failed: HTTP ' . $updatedUser['status']);
    respond(502, false, 'Supabase не смог обновить email. Попробуйте позже.');
}

delete_challenge($tableUrl, $adminHeaders, $userId);
respond(200, true, 'Email успешно подтвержден и изменен');

function respond($status, $success, $message)
{
    http_response_code($status);
    echo json_encode(
        ['success' => $success, 'message' => $message],
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
    );
    exit();
}

function request_json($url, $method, $body, $headers)
{
    $curl = curl_init($url);
    if ($curl === false) {
        respond(502, false, 'Не удалось подключиться к серверу');
    }

    $headers[] = 'Content-Type: application/json';
    curl_setopt_array($curl, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 8,
        CURLOPT_TIMEOUT => 20,
        CURLOPT_HTTPHEADER => $headers,
    ]);
    if ($body !== null) {
        curl_setopt($curl, CURLOPT_POSTFIELDS, json_encode($body));
    }

    $response = curl_exec($curl);
    $status = (int) curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $error = curl_error($curl);
    curl_close($curl);
    if ($response === false) {
        error_log('Email change request failed: ' . $error);
        respond(502, false, 'Сервер авторизации временно недоступен');
    }

    return [
        'status' => $status,
        'data' => json_decode($response, true),
    ];
}

function load_challenge($tableUrl, $headers, $userId)
{
    $result = request_json(
        $tableUrl . '?user_id=eq.' . rawurlencode($userId) . '&select=*',
        'GET',
        null,
        $headers
    );
    if ($result['status'] !== 200 || !is_array($result['data'])) {
        error_log('Email change challenge lookup failed: HTTP ' . $result['status']);
        respond(502, false, 'Не удалось получить состояние подтверждения');
    }
    return $result['data'][0] ?? null;
}

function save_challenge($tableUrl, $headers, $userId, $data)
{
    $data['user_id'] = $userId;
    $headers[] = 'Prefer: resolution=merge-duplicates,return=minimal';
    $result = request_json($tableUrl . '?on_conflict=user_id', 'POST', $data, $headers);
    if ($result['status'] < 200 || $result['status'] >= 300) {
        error_log('Email change challenge save failed: HTTP ' . $result['status']);
        respond(502, false, 'Не удалось сохранить подтверждение email');
    }
}

function update_challenge($tableUrl, $headers, $userId, $data)
{
    $result = request_json(
        $tableUrl . '?user_id=eq.' . rawurlencode($userId),
        'PATCH',
        $data,
        $headers
    );
    if ($result['status'] < 200 || $result['status'] >= 300) {
        error_log('Email change challenge update failed: HTTP ' . $result['status']);
        respond(502, false, 'Не удалось обновить состояние подтверждения');
    }
}

function delete_challenge($tableUrl, $headers, $userId)
{
    $result = request_json(
        $tableUrl . '?user_id=eq.' . rawurlencode($userId),
        'DELETE',
        null,
        $headers
    );
    if ($result['status'] < 200 || $result['status'] >= 300) {
        error_log('Email change challenge cleanup failed: HTTP ' . $result['status']);
        respond(502, false, 'Не удалось завершить смену email');
    }
}

function create_code()
{
    return str_pad((string) random_int(0, 999999), 6, '0', STR_PAD_LEFT);
}

function code_hash($userId, $code, $secret)
{
    return hash_hmac('sha256', $userId . ':' . $code, $secret);
}

function send_email($email, $code)
{
    $phpmailerPath = __DIR__ . '/PHPMailer/';
    foreach (['Exception.php', 'PHPMailer.php', 'SMTP.php'] as $file) {
        if (!file_exists($phpmailerPath . $file)) {
            respond(500, false, 'PHPMailer не найден. Загрузите библиотеку в папку /PHPMailer/');
        }
    }

    require_once $phpmailerPath . 'Exception.php';
    require_once $phpmailerPath . 'PHPMailer.php';
    require_once $phpmailerPath . 'SMTP.php';

    $safeCode = htmlspecialchars($code, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    $mail = new \PHPMailer\PHPMailer\PHPMailer(true);

    try {
        $mail->isSMTP();
        $mail->Host = 'mail.okeanstudio.ru';
        $mail->SMTPAuth = true;
        $mail->Username = 'no-reply';
        $mail->Password = 'pythonJavaCplusplus2013';
        $mail->SMTPSecure = \PHPMailer\PHPMailer\PHPMailer::ENCRYPTION_SMTPS;
        $mail->Port = 465;
        $mail->CharSet = 'UTF-8';
        $mail->SMTPOptions = [
            'ssl' => [
                'verify_peer' => false,
                'verify_peer_name' => false,
                'allow_self_signed' => true,
            ],
        ];

        $mail->setFrom('no-reply@okeanstudio.ru', 'Strazh');
        $mail->addAddress($email);
        $mail->Subject = 'Подтверждение смены email в Strazh';
        $mail->isHTML(true);
        $mail->Body = "
        <!DOCTYPE html>
        <html lang='ru'>
        <head><meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1.0'></head>
        <body style='margin:0;padding:20px;background:#1E1F22;font-family:Arial,sans-serif;color:#fff'>
          <main style='max-width:600px;margin:0 auto;padding:36px;background:#2B2D31;border-radius:16px'>
            <h1 style='text-align:center;color:#5865F2'>Strazh</h1>
            <h2 style='text-align:center'>Подтверждение смены email</h2>
            <p style='color:#B5BAC1;line-height:1.6'>Введите этот код, чтобы подтвердить адрес электронной почты:</p>
            <div style='margin:25px 0;padding:25px;text-align:center;background:#1E1F22;border:2px solid #5865F2;border-radius:12px'>
              <strong style='font-size:46px;letter-spacing:12px;color:#fff'>{$safeCode}</strong>
            </div>
            <p style='color:#B5BAC1'>Код действителен 10 минут. Никому не сообщайте его.</p>
            <p style='margin-top:28px;text-align:center;color:#80848E;font-size:13px'>Если вы не запрашивали смену email, проигнорируйте это письмо.</p>
            <p style='text-align:center'><a style='color:#5865F2' href='https://strazh.chat'>strazh.chat</a></p>
          </main>
        </body>
        </html>
        ";
        $mail->AltBody = "Код для подтверждения смены email в Strazh: $code\n\n"
            . "Код действителен 10 минут. Никому не сообщайте его.\n"
            . "Если вы не запрашивали смену email, проигнорируйте это письмо.";
        $mail->send();
    } catch (\PHPMailer\PHPMailer\Exception $exception) {
        error_log('PHPMailer email change error: ' . $mail->ErrorInfo);
        respond(500, false, 'Не удалось отправить письмо: ' . $mail->ErrorInfo);
    } catch (\Throwable $exception) {
        error_log('Email change send error: ' . $exception->getMessage());
        respond(500, false, 'Не удалось отправить письмо');
    }
}
?>
