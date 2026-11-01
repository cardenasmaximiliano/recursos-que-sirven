<?php
// OpenWA SIMULADO, solo para probar la integración sin vincular un número real.
// Se levanta con:  php -S 127.0.0.1:2799 simulador/openwa_simulado.php
// Responde igual que OpenWA en lo que usa la API:
//   GET  /api/health
//   GET  /api/sessions/{id}                       -> {"id":..., "status":"ready"}
//   POST /api/sessions/{id}/messages/send-text    -> 201 {"id":"sim-N"} (guarda el mensaje en enviados.jsonl)
//   GET  /_enviados                               -> lo que "envió" (para verificar)
//   POST /_reiniciar                              -> borra lo guardado
// Trucos para probar fallos: un número que empieza con 5490000 devuelve 500 (transitorio) y uno que empieza con
// 5491111 devuelve 400 (definitivo). Sin la cabecera X-API-Key correcta (clave-de-prueba) devuelve 401.
declare(strict_types=1);

const CLAVE = 'clave-de-prueba';
$archivo = __DIR__ . '/enviados.jsonl';
$ruta = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$metodo = $_SERVER['REQUEST_METHOD'] ?? 'GET';

function responder(int $codigo, array $datos): never
{
    http_response_code($codigo);
    header('Content-Type: application/json; charset=UTF-8');
    echo json_encode($datos, JSON_UNESCAPED_UNICODE);
    exit;
}

if ($ruta === '/api/health') {
    responder(200, ['status' => 'ok']);
}
if ($ruta === '/_enviados') {
    $lineas = is_file($archivo) ? file($archivo, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) : [];
    responder(200, array_map(static fn(string $l): array => json_decode($l, true), $lineas));
}
if ($ruta === '/_reiniciar' && $metodo === 'POST') {
    @unlink($archivo);
    responder(200, ['ok' => true]);
}

if (($_SERVER['HTTP_X_API_KEY'] ?? '') !== CLAVE) {
    responder(401, ['message' => 'API key inválida']);
}
if (preg_match('#^/api/sessions/([^/]+)$#', $ruta) && $metodo === 'GET') {
    responder(200, ['id' => basename($ruta), 'status' => 'ready']);
}
if (preg_match('#^/api/sessions/([^/]+)/messages/send-text$#', $ruta) && $metodo === 'POST') {
    $cuerpo = json_decode(file_get_contents('php://input') ?: '', true);
    $chat = (string) ($cuerpo['chatId'] ?? '');
    $texto = (string) ($cuerpo['text'] ?? '');
    if (!str_ends_with($chat, '@c.us') || $texto === '') {
        responder(400, ['message' => 'chatId o text inválidos']);
    }
    if (str_starts_with($chat, '5490000')) {
        responder(500, ['message' => 'Error simulado del servidor']);
    }
    if (str_starts_with($chat, '5491111')) {
        responder(400, ['message' => 'Número inválido (simulado)']);
    }
    $n = is_file($archivo) ? count(file($archivo)) + 1 : 1;
    file_put_contents($archivo, json_encode(['chatId' => $chat, 'text' => $texto], JSON_UNESCAPED_UNICODE) . PHP_EOL, FILE_APPEND | LOCK_EX);
    responder(201, ['id' => 'sim-' . $n]);
}
responder(404, ['message' => 'No existe']);
