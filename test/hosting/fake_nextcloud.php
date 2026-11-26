<?php
// Attrappe einer Nextcloud für test/hosting/run.sh (php -S … fake_nextcloud.php)
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];
if ($path === '/status.php') {
    header('Content-Type: application/json');
    echo json_encode(['installed' => true, 'versionstring' => '31.0.0', 'productname' => 'Nextcloud']);
} elseif ($path === '/big.pdf') {
    // 40 MB – mehr, als der Proxy im Test an Arbeitsspeicher bekommt
    header('Content-Type: application/pdf');
    header('Content-Length: ' . (40 * 1024 * 1024));
    header('ETag: "gross"');
    $block = str_repeat('N', 1024 * 1024);
    for ($i = 0; $i < 40; $i++) {
        echo $block;
    }
} elseif ($method === 'PROPFIND') {
    http_response_code(207);
    header('Content-Type: application/xml; charset=utf-8');
    header('DAV: 1, 3');
    echo '<d:multistatus xmlns:d="DAV:" depth="' . ($_SERVER['HTTP_DEPTH'] ?? '') . '" auth="' . ($_SERVER['HTTP_AUTHORIZATION'] ?? '') . '">' . file_get_contents('php://input') . '</d:multistatus>';
} elseif ($method === 'PUT') {
    http_response_code(201);
    header('ETag: "' . md5(file_get_contents('php://input')) . '"');
} elseif ($method === 'DELETE') {
    http_response_code(204);
} else {
    http_response_code(404);
    echo 'nicht gefunden';
}
