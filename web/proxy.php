<?php
/**
 * Notencloud WebDAV CORS Proxy for Hetzner Storage Share / Nextcloud
 * 
 * Ermöglicht der Flutter Web PWA den reibungslosen Zugriff auf Hetzner Storage Share
 * ohne Cross-Origin-Blockaden (CORS) im Browser.
 */

// 0. Optionale Einschränkung über proxy.config.php (liegt neben dieser Datei):
//    <?php return [
//        'hosts'   => ['nx12345.your-storageshare.de'],   // erlaubte Nextcloud-Server
//        'origins' => ['https://beispiel.github.io'],      // Seiten, die den Proxy nutzen dürfen
//    ];
//    Ohne diese Datei leitet der Proxy an jeden Server weiter. Sobald der Proxy
//    öffentlich erreichbar ist, sollte sie angelegt werden – install.php
//    erledigt das bei der Einrichtung.
$config = [];
$configFile = __DIR__ . '/proxy.config.php';
if (is_file($configFile)) {
    $loaded = include $configFile;
    if (is_array($loaded)) {
        $config = $loaded;
    }
}
$allowedHosts = array_map('strtolower', $config['hosts'] ?? []);
$allowedOrigins = array_map(function ($o) {
    return rtrim(strtolower($o), '/');
}, $config['origins'] ?? []);

// 1. CORS Headers setzen
$origin = isset($_SERVER['HTTP_ORIGIN']) ? rtrim(strtolower($_SERVER['HTTP_ORIGIN']), '/') : '';
if (empty($allowedOrigins)) {
    header("Access-Control-Allow-Origin: *");
} else {
    header("Vary: Origin");
    if ($origin !== '' && in_array($origin, $allowedOrigins, true)) {
        header("Access-Control-Allow-Origin: " . $_SERVER['HTTP_ORIGIN']);
    } elseif ($origin !== '') {
        // Fremde Seite: nicht bedienen
        http_response_code(403);
        header("Content-Type: text/plain; charset=utf-8");
        echo "Fehler: Diese Seite darf den Proxy nicht nutzen.";
        exit;
    }
}
header("Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS, PROPFIND, MKCOL, MOVE, COPY");
header("Access-Control-Allow-Headers: Authorization, Content-Type, Depth, Destination, Overwrite, OCS-APIREQUEST, User-Agent, X-Requested-With");
header("Access-Control-Expose-Headers: ETag, Content-Length, Content-Type, DAV");
header("Access-Control-Max-Age: 86400");

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

// Nur freigegebene Nextcloud-Server ansprechen (falls eingeschränkt)
if (!empty($allowedHosts)) {
    $targetHost = strtolower((string) parse_url($targetUrl, PHP_URL_HOST));
    if ($targetHost === '' || !in_array($targetHost, $allowedHosts, true)) {
        http_response_code(403);
        header("Content-Type: text/plain; charset=utf-8");
        echo "Fehler: Dieser Server ist für den Proxy nicht freigegeben.";
        exit;
    }
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
    if (in_array($lower, ['host', 'content-length', 'accept-encoding', 'connection', 'origin', 'referer', 'cookie'])) {
        continue;
    }
    $forwardHeaders[] = "$name: $value";
}

// Lange Downloads (große Partituren) nicht vom PHP-Zeitlimit abbrechen lassen.
@set_time_limit(600);

curl_setopt($ch, CURLOPT_CUSTOMREQUEST, $_SERVER['REQUEST_METHOD']);
curl_setopt($ch, CURLOPT_HTTPHEADER, $forwardHeaders);
curl_setopt($ch, CURLOPT_FOLLOWLOCATION, false);
curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 15);
curl_setopt($ch, CURLOPT_TIMEOUT, 600);
if ($_SERVER['REQUEST_METHOD'] === 'HEAD') {
    curl_setopt($ch, CURLOPT_NOBODY, true);
}

// Request-Body weiterreichen (z.B. XML bei PROPFIND oder Bytes bei PUT)
if ($_SERVER['REQUEST_METHOD'] !== 'GET' && $_SERVER['REQUEST_METHOD'] !== 'HEAD') {
    $input = file_get_contents('php://input');
    if (!empty($input)) {
        curl_setopt($ch, CURLOPT_POSTFIELDS, $input);
    }
}

// 4. Antwort durchreichen, ohne sie im Arbeitsspeicher zu sammeln: Auf einfachem
//    Webhosting ist der Speicher knapp, Noten-PDFs können aber groß sein.
$responseHeaders = [];
$started = false;

// Schickt Statuscode und die wichtigen Header der Nextcloud-Antwort an den Browser.
$startResponse = function () use ($ch, &$responseHeaders, &$started) {
    if ($started) {
        return;
    }
    $started = true;
    while (ob_get_level() > 0) {
        ob_end_clean();
    }
    http_response_code(curl_getinfo($ch, CURLINFO_HTTP_CODE) ?: 502);
    foreach ($responseHeaders as $line) {
        $lower = strtolower($line);
        foreach (['content-type:', 'etag:', 'content-length:', 'dav:', 'content-range:', 'accept-ranges:', 'last-modified:'] as $wanted) {
            if (strpos($lower, $wanted) === 0) {
                header($line);
                break;
            }
        }
    }
};

curl_setopt($ch, CURLOPT_HEADERFUNCTION, function ($ch, $line) use (&$responseHeaders) {
    $trimmed = trim($line);
    if (stripos($trimmed, 'HTTP/') === 0) {
        // Neue Statuszeile (z.B. nach "100 Continue"): Header von vorn sammeln.
        $responseHeaders = [];
    } elseif ($trimmed !== '') {
        $responseHeaders[] = $trimmed;
    }
    return strlen($line);
});
curl_setopt($ch, CURLOPT_WRITEFUNCTION, function ($ch, $chunk) use ($startResponse) {
    $startResponse();
    echo $chunk;
    flush();
    return strlen($chunk);
});

curl_exec($ch);

if (curl_errno($ch) && !$started) {
    http_response_code(502);
    header("Content-Type: text/plain; charset=utf-8");
    echo "Proxy-Fehler: " . curl_error($ch);
    curl_close($ch);
    exit;
}

// Antworten ohne Inhalt (z.B. 201 nach PUT, 204 nach DELETE)
$startResponse();
curl_close($ch);
