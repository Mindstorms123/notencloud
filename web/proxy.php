<?php
/**
 * Notencloud WebDAV CORS Proxy for Hetzner Storage Share / Nextcloud
 * 
 * Ermöglicht der Flutter Web PWA den reibungslosen Zugriff auf Hetzner Storage Share
 * ohne Cross-Origin-Blockaden (CORS) im Browser.
 */

// 1. CORS Headers setzen
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS, PROPFIND, MKCOL, MOVE, COPY");
header("Access-Control-Allow-Headers: Authorization, Content-Type, Depth, OCS-APIREQUEST, User-Agent, X-Requested-With");
header("Access-Control-Expose-Headers: ETag, Content-Length, Content-Type, DAV");

// Preflight OPTIONS Anfragen sofort mit 200 OK beantworten
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// 2. Ziel-URL ermitteln
$targetUrl = isset($_GET['url']) ? $_GET['url'] : '';
if (empty($targetUrl)) {
    http_response_code(400);
    header("Content-Type: text/plain; charset=utf-8");
    echo "Fehler: Parameter 'url' fehlt.";
    exit;
}

// Nur http und https erlauben
if (!preg_match('#^https?://#i', $targetUrl)) {
    http_response_code(400);
    header("Content-Type: text/plain; charset=utf-8");
    echo "Fehler: Ungültige Ziel-URL.";
    exit;
}

// 3. Request mit cURL an Hetzner Storage Share weiterleiten
$ch = curl_init($targetUrl);

// Alle Header der Anfrage ermitteln (inkl. Basic Auth, Depth, OCS-APIREQUEST)
$forwardHeaders = [];
if (function_exists('getallheaders')) {
    $incomingHeaders = getallheaders();
} else {
    $incomingHeaders = [];
    foreach ($_SERVER as $key => $value) {
        if (substr($key, 0, 5) === 'HTTP_') {
            $name = str_replace(' ', '-', ucwords(strtolower(str_replace('_', ' ', substr($key, 5)))));
            $incomingHeaders[$name] = $value;
        } elseif ($key === 'CONTENT_TYPE') {
            $incomingHeaders['Content-Type'] = $value;
        }
    }
}

foreach ($incomingHeaders as $name => $value) {
    $lower = strtolower($name);
    // Hop-by-hop und Host-Header nicht weiterreichen
    if (in_array($lower, ['host', 'content-length', 'accept-encoding', 'connection'])) {
        continue;
    }
    $forwardHeaders[] = "$name: $value";
}

curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $_SERVER['REQUEST_METHOD']);
curl_setopt($ch, CURLOPT_HTTPHEADER, $forwardHeaders);
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_HEADER, true);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, false);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
curl_setopt($ch, CURLOPT_TIMEOUT, 60);

// Request-Body weiterreichen (z.B. XML bei PROPFIND oder Bytes bei PUT)
if ($_SERVER['REQUEST_METHOD'] !== 'GET' && $_SERVER['REQUEST_METHOD'] !== 'HEAD') {
    $input = file_get_contents('php://input');
    if (!empty($input)) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, $input);
    }
}

$response = curl_exec($ch);

if (curl_errno($ch)) {
    http_response_code(502);
    header("Content-Type: text/plain; charset=utf-8");
    echo "Proxy-Fehler: " . curl_error($ch);
    curl_close($ch);
    exit;
}

$headerSize = curl_getinfo($ch, CURLINFO_HEADER_SIZE);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

$rawHeaders = substr($response, 0, $headerSize);
$body = substr($response, $headerSize);

http_response_code($httpCode);

// Wichtige Header aus der Nextcloud-Antwort an den Browser weiterleiten
$headerLines = explode("\r\n", $rawHeaders);
foreach ($headerLines as $line) {
    $lower = strtolower($line);
    if (strpos($lower, 'content-type:') === 0 ||
        strpos($lower, 'etag:') === 0 ||
        strpos($lower, 'content-length:') === 0 ||
        strpos($lower, 'dav:') === 0) {
        header($line);
    }
}

echo $body;
