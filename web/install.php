<?php
/**
 * Notencloud – Einrichtung und Updates auf einfachem Webhosting (PHP, kein SSH nötig)
 *
 * 1. Diese eine Datei in einen EIGENEN, LEEREN Ordner hochladen (eigene Subdomain
 *    oder Unterordner) – nicht in den Ordner einer bestehenden Webseite.
 * 2. Im Browser aufrufen:  https://noten.euer-verein.de/install.php
 * 3. Formular ausfüllen – fertig.
 *
 * Das Skript lädt die aktuelle Web-App von GitHub, entpackt sie neben sich und
 * schreibt die Einstellungen des Vereins:
 *   config.json          – Vereinsname, Nextcloud-Adresse, Notenordner (liest die App)
 *   proxy.config.php     – beschränkt proxy.php auf die eigene Nextcloud
 *   install.config.php   – Passwort (als Hash) und installierte Fassung
 * Später dient dieselbe Adresse zum Aktualisieren und zum Ändern der Einstellungen.
 *
 * Ohne Internetzugriff des Webhostings: notencloud-web.zip aus dem GitHub-Release
 * neben diese Datei legen – dann wird das Archiv verwendet.
 */

declare(strict_types=1);

const NC_DEFAULT_SOURCE = 'https://github.com/Mindstorms123/notencloud/releases/latest/download/';
const NC_ZIP_NAME = 'notencloud-web.zip';
const NC_STATE_FILE = 'install.config.php';
const NC_PROXY_CONFIG = 'proxy.config.php';
const NC_APP_CONFIG = 'config.json';
const NC_KONZERTMEISTER_HOST = 'rest.konzertmeister.app';
/** Diese Dateien gehören dem Verein und werden bei Updates nie überschrieben. */
const NC_KEEP = [NC_APP_CONFIG, NC_PROXY_CONFIG, NC_STATE_FILE];

error_reporting(E_ALL);
ini_set('display_errors', '0');
header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
header('X-Robots-Tag: noindex');

// ---------------------------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------------------------

function nc_h($value): string
{
    return htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
}

function nc_source(): string
{
    $env = getenv('NOTENCLOUD_RELEASE_BASE');
    return rtrim($env !== false && $env !== '' ? $env : NC_DEFAULT_SOURCE, '/') . '/';
}

function nc_state(): ?array
{
    $file = __DIR__ . '/' . NC_STATE_FILE;
    if (!is_file($file)) {
        return null;
    }
    $data = include $file;
    return is_array($data) && !empty($data['password_hash']) ? $data : null;
}

function nc_write_php_config(string $name, array $data, string $comment): void
{
    $code = "<?php\n// $comment\nreturn " . var_export($data, true) . ";\n";
    nc_write(__DIR__ . '/' . $name, $code);
    if (function_exists('opcache_invalidate')) {
        @opcache_invalidate(__DIR__ . '/' . $name, true);
    }
}

function nc_write(string $path, string $content): void
{
    if (@file_put_contents($path, $content, LOCK_EX) === false) {
        throw new RuntimeException('Die Datei ' . basename($path) . ' konnte nicht geschrieben werden. Hat der Ordner Schreibrechte?');
    }
}

function nc_is_https(): bool
{
    return (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
        || strtolower($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https';
}

/** Adresse des Ordners, in dem die App liegt, z. B. https://noten.verein.de/ */
function nc_app_url(): string
{
    $host = $_SERVER['HTTP_HOST'] ?? 'localhost';
    $dir = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
    return (nc_is_https() ? 'https' : 'http') . '://' . $host . $dir . '/';
}

/** Ursprünge, von denen aus die App den Proxy nutzen darf (mit und ohne „www.“). */
function nc_origins(): array
{
    $scheme = nc_is_https() ? 'https' : 'http';
    $host = strtolower($_SERVER['HTTP_HOST'] ?? 'localhost');
    $hosts = [$host];
    $hosts[] = strpos($host, 'www.') === 0 ? substr($host, 4) : 'www.' . $host;
    return array_map(function ($h) use ($scheme) {
        return $scheme . '://' . $h;
    }, $hosts);
}

function nc_is_local_host(string $host): bool
{
    return in_array($host, ['localhost', '127.0.0.1', '[::1]'], true);
}

/** Bringt die eingegebene Nextcloud-Adresse in Form; wirft bei Unsinn. */
function nc_normalize_server(string $input): string
{
    $url = trim($input);
    if ($url === '') {
        throw new InvalidArgumentException('Bitte die Adresse der Nextcloud eintragen.');
    }
    if (!preg_match('#^https?://#i', $url)) {
        $url = 'https://' . $url;
    }
    // Aus dem Browser kopierte Adressen enden oft auf /index.php/apps/files/…
    $url = preg_replace('#/(index\.php|apps|login|remote\.php)(/.*)?$#i', '', $url);
    $url = rtrim($url, '/');
    $parts = parse_url($url);
    if ($parts === false || empty($parts['host']) || isset($parts['query']) || isset($parts['user'])) {
        throw new InvalidArgumentException('Die Nextcloud-Adresse ist nicht gültig. Beispiel: https://nx12345.your-storageshare.de');
    }
    if (strtolower($parts['scheme']) !== 'https' && !nc_is_local_host(strtolower($parts['host']))) {
        throw new InvalidArgumentException('Die Nextcloud-Adresse muss mit https:// beginnen.');
    }
    return $url;
}

function nc_normalize_folder(string $input): string
{
    $folder = '/' . trim(str_replace('\\', '/', trim($input)), '/');
    return $folder === '/' && trim($input) === '' ? '/Noten' : $folder;
}

/** Leerer Text oder ein Link zum Konzertmeister-Kalender. */
function nc_normalize_konzertmeister(string $input): string
{
    $url = trim($input);
    if ($url === '') {
        return '';
    }
    $host = strtolower((string) parse_url($url, PHP_URL_HOST));
    if (stripos($url, 'https://') !== 0 || $host !== NC_KONZERTMEISTER_HOST) {
        throw new InvalidArgumentException('Der Konzertmeister-Link muss mit https://' . NC_KONZERTMEISTER_HOST . '/ beginnen (Konzertmeister › Webseiten-Einbindung).');
    }
    return $url;
}

function nc_http_get(string $url, int $timeout = 20): array
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS => 5,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => $timeout,
        CURLOPT_USERAGENT => 'Notencloud-Installer',
    ]);
    $body = curl_exec($ch);
    $result = [
        'status' => (int) curl_getinfo($ch, CURLINFO_HTTP_CODE),
        'body' => is_string($body) ? $body : '',
        'error' => curl_error($ch),
    ];
    curl_close($ch);
    return $result;
}

/** Prüft, ob unter der Adresse wirklich eine Nextcloud antwortet. */
function nc_check_nextcloud(string $server): string
{
    $res = nc_http_get($server . '/status.php');
    if ($res['error'] !== '') {
        throw new RuntimeException('Die Nextcloud ist vom Webhosting aus nicht erreichbar (' . $res['error'] . '). Stimmt die Adresse?');
    }
    $json = json_decode($res['body'], true);
    if ($res['status'] !== 200 || !is_array($json) || !array_key_exists('installed', $json)) {
        throw new RuntimeException('Unter ' . $server . ' antwortet keine Nextcloud (Antwort ' . $res['status'] . '). Bitte die Adresse so eintragen, wie sie im Browser nach dem Anmelden in der Adresszeile steht – ohne alles hinter dem ersten „/“.');
    }
    return (string) ($json['versionstring'] ?? '');
}

/** Fassung, die als neuestes Release bereitliegt (oder null, wenn nicht ermittelbar). */
function nc_latest_version(): ?array
{
    if (is_file(__DIR__ . '/' . NC_ZIP_NAME)) {
        return null;
    }
    $res = nc_http_get(nc_source() . 'version.json', 10);
    $json = $res['status'] === 200 ? json_decode($res['body'], true) : null;
    return is_array($json) && !empty($json['version']) ? $json : null;
}

/** Liefert den Pfad zum Web-Paket: das Archiv neben dem Skript oder ein frischer Download. */
function nc_fetch_zip(bool &$isTemp): string
{
    $local = __DIR__ . '/' . NC_ZIP_NAME;
    if (is_file($local)) {
        $isTemp = false;
        return $local;
    }
    $isTemp = true;
    $target = __DIR__ . '/.notencloud-download-' . bin2hex(random_bytes(6)) . '.zip';
    $fp = @fopen($target, 'wb');
    if ($fp === false) {
        throw new RuntimeException('In diesem Ordner darf PHP keine Dateien anlegen. Bitte die Schreibrechte des Ordners prüfen.');
    }
    $ch = curl_init(nc_source() . NC_ZIP_NAME);
    curl_setopt_array($ch, [
        CURLOPT_FILE => $fp,
        CURLOPT_FOLLOWLOCATION => true,
        CURLOPT_MAXREDIRS => 5,
        CURLOPT_FAILONERROR => true,
        CURLOPT_CONNECTTIMEOUT => 15,
        CURLOPT_TIMEOUT => 300,
        CURLOPT_USERAGENT => 'Notencloud-Installer',
    ]);
    $ok = curl_exec($ch);
    $error = curl_error($ch);
    $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    fclose($fp);
    if ($ok === false || filesize($target) < 1000) {
        @unlink($target);
        $hint = $status === 404
            ? 'Im neuesten Release liegt (noch) kein Web-Paket. Bitte in ein paar Minuten erneut versuchen'
            : 'Der Download ist fehlgeschlagen (' . ($error !== '' ? $error : 'Antwort ' . $status) . ')';
        throw new RuntimeException($hint . ' – oder ' . NC_ZIP_NAME . ' von der Release-Seite laden und neben install.php hochladen.');
    }
    return $target;
}

function nc_entry_allowed(string $name): bool
{
    if ($name === '' || $name[0] === '/' || strpos($name, '\\') !== false || strpos($name, "\0") !== false) {
        return false;
    }
    foreach (explode('/', $name) as $segment) {
        if ($segment === '..') {
            return false;
        }
    }
    return !in_array($name, NC_KEEP, true);
}

function nc_put_entry(string $dest, string $name, string $content): void
{
    $path = $dest . '/' . $name;
    $dir = dirname($path);
    if (!is_dir($dir) && !@mkdir($dir, 0755, true) && !is_dir($dir)) {
        throw new RuntimeException('Der Ordner ' . $dir . ' konnte nicht angelegt werden.');
    }
    nc_write($path, $content);
}

/** Entpackt das Web-Paket; Einstellungen des Vereins bleiben unberührt. */
function nc_unzip(string $zipPath, string $dest): int
{
    $count = 0;
    if (class_exists('ZipArchive')) {
        $zip = new ZipArchive();
        if ($zip->open($zipPath) !== true) {
            throw new RuntimeException('Das Web-Paket ist beschädigt und lässt sich nicht öffnen.');
        }
        for ($i = 0; $i < $zip->numFiles; $i++) {
            $name = (string) $zip->getNameIndex($i);
            if (substr($name, -1) === '/' || !nc_entry_allowed($name)) {
                continue;
            }
            $content = $zip->getFromIndex($i);
            if ($content === false) {
                throw new RuntimeException('Die Datei ' . $name . ' im Web-Paket ist beschädigt.');
            }
            nc_put_entry($dest, $name, $content);
            $count++;
        }
        $zip->close();
        return $count;
    }
    return nc_unzip_plain($zipPath, $dest);
}

/** ZIP-Leser ohne die PHP-Erweiterung „zip“ (braucht nur zlib). */
function nc_unzip_plain(string $zipPath, string $dest): int
{
    $broken = new RuntimeException('Das Web-Paket ist beschädigt und lässt sich nicht öffnen.');
    $fp = @fopen($zipPath, 'rb');
    $size = (int) @filesize($zipPath);
    if ($fp === false || $size < 22) {
        throw $broken;
    }
    $tailLength = min($size, 65557);
    fseek($fp, -$tailLength, SEEK_END);
    $tail = (string) fread($fp, $tailLength);
    $pos = strrpos($tail, "PK\x05\x06");
    if ($pos === false) {
        throw $broken;
    }
    $end = unpack('vdisk/vcdDisk/vdiskCount/vcount/VcdSize/VcdOffset', substr($tail, $pos + 4, 16));
    fseek($fp, $end['cdOffset']);
    $directory = (string) fread($fp, $end['cdSize']);
    $offset = 0;
    $count = 0;
    for ($i = 0; $i < $end['count']; $i++) {
        if (substr($directory, $offset, 4) !== "PK\x01\x02") {
            throw $broken;
        }
        $entry = unpack(
            'vmade/vneed/vflags/vmethod/vtime/vdate/Vcrc/VcompSize/Vsize/vnameLen/vextraLen/vcommentLen/vdiskNo/vintAttr/VextAttr/Vlocal',
            substr($directory, $offset + 4, 42)
        );
        $name = substr($directory, $offset + 46, $entry['nameLen']);
        $offset += 46 + $entry['nameLen'] + $entry['extraLen'] + $entry['commentLen'];
        if (substr($name, -1) === '/' || !nc_entry_allowed($name)) {
            continue;
        }
        fseek($fp, $entry['local']);
        $local = (string) fread($fp, 30);
        if (substr($local, 0, 4) !== "PK\x03\x04") {
            throw $broken;
        }
        $lengths = unpack('vnameLen/vextraLen', substr($local, 26, 4));
        fseek($fp, $entry['local'] + 30 + $lengths['nameLen'] + $lengths['extraLen']);
        $raw = $entry['compSize'] > 0 ? (string) fread($fp, $entry['compSize']) : '';
        if ($entry['method'] === 0) {
            $content = $raw;
        } elseif ($entry['method'] === 8) {
            $content = $raw === '' ? '' : @gzinflate($raw);
        } else {
            throw $broken;
        }
        if ($content === false || strlen($content) !== $entry['size'] || crc32($content) !== $entry['crc']) {
            throw new RuntimeException('Die Datei ' . $name . ' im Web-Paket ist beschädigt.');
        }
        nc_put_entry($dest, $name, $content);
        $count++;
    }
    fclose($fp);
    return $count;
}

/** Lädt und entpackt die App; gibt die installierte Fassung zurück. */
function nc_install_app(): string
{
    @set_time_limit(600);
    $isTemp = false;
    $zip = nc_fetch_zip($isTemp);
    try {
        $count = nc_unzip($zip, __DIR__);
    } finally {
        // Das Archiv wird nicht mehr gebraucht (und soll nicht öffentlich herumliegen).
        @unlink($zip);
    }
    if ($count === 0 || !is_file(__DIR__ . '/index.html') || !is_file(__DIR__ . '/proxy.php')) {
        throw new RuntimeException('Das Web-Paket enthält nicht die erwarteten Dateien.');
    }
    // Überbleibsel früherer Anleitungen
    @unlink(__DIR__ . '/unzip.php');
    $version = json_decode((string) @file_get_contents(__DIR__ . '/version.json'), true);
    return is_array($version) && !empty($version['version']) ? (string) $version['version'] : 'unbekannt';
}

/** Schreibt config.json (für die App) und proxy.config.php (für den Proxy). */
function nc_write_settings(array $settings): void
{
    $json = [
        'club' => $settings['club'],
        'server' => $settings['server'],
        'folder' => $settings['folder'],
        'konzertmeister' => $settings['konzertmeister'],
    ];
    nc_write(
        __DIR__ . '/' . NC_APP_CONFIG,
        json_encode($json, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) . "\n"
    );
    $hosts = [strtolower((string) parse_url($settings['server'], PHP_URL_HOST))];
    if ($settings['konzertmeister'] !== '') {
        $hosts[] = NC_KONZERTMEISTER_HOST;
    }
    nc_write_php_config(NC_PROXY_CONFIG, [
        'hosts' => $hosts,
        'origins' => nc_origins(),
    ], 'Notencloud-Proxy: nur die eigene Nextcloud, nur von der eigenen Notencloud-Seite aus. Von install.php geschrieben.');
}

function nc_read_settings(): array
{
    $json = json_decode((string) @file_get_contents(__DIR__ . '/' . NC_APP_CONFIG), true);
    $json = is_array($json) ? $json : [];
    return [
        'club' => (string) ($json['club'] ?? ''),
        'server' => (string) ($json['server'] ?? ''),
        'folder' => (string) ($json['folder'] ?? '/Noten'),
        'konzertmeister' => (string) ($json['konzertmeister'] ?? ''),
    ];
}

/** Liest und prüft die Formularfelder. */
function nc_settings_from_post(): array
{
    $club = trim((string) ($_POST['club'] ?? ''));
    if ($club === '' || mb_strlen($club) > 80) {
        throw new InvalidArgumentException('Bitte den Namen des Vereins eintragen (höchstens 80 Zeichen).');
    }
    $server = nc_normalize_server((string) ($_POST['server'] ?? ''));
    nc_check_nextcloud($server);
    return [
        'club' => $club,
        'server' => $server,
        'folder' => nc_normalize_folder((string) ($_POST['folder'] ?? '')),
        'konzertmeister' => nc_normalize_konzertmeister((string) ($_POST['konzertmeister'] ?? '')),
    ];
}

/**
 * Dateien, die schon im Ordner liegen und nicht zu Notencloud gehören – etwa die
 * Webseite des Vereins. Die Einrichtung würde gleichnamige Dateien überschreiben.
 */
function nc_foreign_files(): array
{
    $own = ['.', '..', basename(__FILE__), NC_ZIP_NAME];
    $found = [];
    foreach ((array) @scandir(__DIR__) as $name) {
        if (in_array($name, $own, true) || strpos($name, '.notencloud-download-') === 0) {
            continue;
        }
        $found[] = is_dir(__DIR__ . '/' . $name) ? $name . '/' : $name;
    }
    return $found;
}

function nc_requirements(): array
{
    $checks = [];
    $checks[] = ['PHP 7.4 oder neuer', PHP_VERSION_ID >= 70400, 'Installiert ist PHP ' . PHP_VERSION . '. Im Kundenmenü des Webhostings eine neuere PHP-Version wählen.'];
    $checks[] = ['PHP-Erweiterung „curl“', function_exists('curl_init'), 'Ohne curl kann die App die Nextcloud nicht erreichen. Im Kundenmenü aktivieren.'];
    $checks[] = ['PHP-Erweiterung „zlib“ oder „zip“', class_exists('ZipArchive') || function_exists('gzinflate'), 'Zum Entpacken der App nötig. Im Kundenmenü aktivieren.'];
    $checks[] = ['Ordner ist beschreibbar', is_writable(__DIR__), 'PHP darf in diesem Ordner keine Dateien anlegen. Schreibrechte des Ordners prüfen.'];
    $checks[] = ['Aufruf über https://', nc_is_https() || nc_is_local_host(strtolower(explode(':', $_SERVER['HTTP_HOST'] ?? '')[0])), 'Die App braucht eine verschlüsselte Verbindung. Im Kundenmenü ein SSL-Zertifikat (Let’s Encrypt) für die Domain einschalten und diese Seite mit https:// aufrufen.'];
    return $checks;
}

// ---------------------------------------------------------------------------
// Ablauf
// ---------------------------------------------------------------------------

session_name('notencloud_install');
session_set_cookie_params(['httponly' => true, 'samesite' => 'Strict', 'secure' => nc_is_https()]);
session_start();
if (empty($_SESSION['token'])) {
    $_SESSION['token'] = bin2hex(random_bytes(16));
}

$state = nc_state();
$foreign = $state === null ? nc_foreign_files() : [];
$requirements = nc_requirements();
$ready = !in_array(false, array_column($requirements, 1), true);
$isPost = ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST';
$action = $isPost ? (string) ($_POST['action'] ?? '') : '';
$error = '';
$notice = '';
$view = $state === null ? 'install' : (!empty($_SESSION['admin']) ? 'admin' : 'login');
$form = $state === null
    ? ['club' => '', 'server' => '', 'folder' => '/Noten', 'konzertmeister' => '']
    : nc_read_settings();

if ($isPost && !hash_equals($_SESSION['token'], (string) ($_POST['token'] ?? ''))) {
    $error = 'Die Seite war zu lange offen. Bitte noch einmal absenden.';
    $action = '';
}

try {
    if ($action === 'install' && $state === null && $ready) {
        $form = array_merge($form, array_map('strval', array_intersect_key($_POST, $form)));
        $password = (string) ($_POST['password'] ?? '');
        if (strlen($password) < 10) {
            throw new InvalidArgumentException('Das Passwort für spätere Updates braucht mindestens 10 Zeichen.');
        }
        if ($foreign !== [] && ($_POST['overwrite'] ?? '') !== 'ja') {
            throw new InvalidArgumentException('In diesem Ordner liegen schon Dateien. Bitte unten bestätigen, dass hier eingerichtet werden darf – oder install.php in einen eigenen, leeren Ordner legen.');
        }
        $settings = nc_settings_from_post();
        $version = nc_install_app();
        nc_write_settings($settings);
        nc_write_php_config(NC_STATE_FILE, [
            'password_hash' => password_hash($password, PASSWORD_DEFAULT),
            'version' => $version,
            'installed_at' => date('c'),
        ], 'Notencloud-Einrichtung: Passwort (Hash) und installierte Fassung. Von install.php geschrieben.');
        session_regenerate_id(true);
        $_SESSION['admin'] = true;
        $state = nc_state();
        $form = $settings;
        $view = 'done';
    } elseif ($action === 'login' && $state !== null) {
        if (password_verify((string) ($_POST['password'] ?? ''), $state['password_hash'])) {
            session_regenerate_id(true);
            $_SESSION['admin'] = true;
            $view = 'admin';
        } else {
            sleep(2);
            $error = 'Das Passwort stimmt nicht.';
        }
    } elseif ($action === 'logout') {
        $_SESSION = [];
        session_destroy();
        $view = $state === null ? 'install' : 'login';
        session_start();
        $_SESSION['token'] = bin2hex(random_bytes(16));
    } elseif ($action === 'update' && $view === 'admin') {
        $version = nc_install_app();
        nc_write_php_config(NC_STATE_FILE, array_merge($state, [
            'version' => $version,
            'updated_at' => date('c'),
        ]), 'Notencloud-Einrichtung: Passwort (Hash) und installierte Fassung. Von install.php geschrieben.');
        $state = nc_state();
        $notice = 'Die App ist jetzt auf dem Stand ' . $version . '. Auf den Geräten kommt die neue Fassung beim nächsten Öffnen an.';
    } elseif ($action === 'settings' && $view === 'admin') {
        $form = array_merge($form, array_map('strval', array_intersect_key($_POST, $form)));
        $settings = nc_settings_from_post();
        nc_write_settings($settings);
        $form = $settings;
        $notice = 'Die Einstellungen sind gespeichert.';
    }
} catch (InvalidArgumentException $e) {
    $error = $e->getMessage();
} catch (Throwable $e) {
    $error = $e->getMessage();
}

$latest = null;
if ($view === 'admin' && function_exists('curl_init')) {
    $latest = nc_latest_version();
}
$appUrl = nc_app_url();
$setupLink = 'notencloud://setup?server=' . rawurlencode($form['server']) . '&folder=' . rawurlencode($form['folder']);
$token = $_SESSION['token'];

/** Die vier Felder, die Einrichtung und Einstellungen gemeinsam haben. */
function nc_fields(array $form): void
{
    ?>
    <label>Name des Vereins
      <input name="club" required maxlength="80" value="<?= nc_h($form['club']) ?>" placeholder="Musikverein Beispielstadt">
      <small>Steht auf Ablaufplänen und in Einladungstexten.</small>
    </label>
    <label>Adresse der Nextcloud (Storage Share)
      <input name="server" required inputmode="url" value="<?= nc_h($form['server']) ?>" placeholder="https://nx12345.your-storageshare.de">
      <small>So wie sie im Browser steht, wenn ihr eure Nextcloud öffnet.</small>
    </label>
    <label>Notenordner in der Nextcloud
      <input name="folder" value="<?= nc_h($form['folder']) ?>" placeholder="/Noten">
      <small>Der Ordner, in dem die Stücke liegen. Mitglieder können ihn in der App anpassen.</small>
    </label>
    <label>Konzertmeister-Kalender <em>(freiwillig)</em>
      <input name="konzertmeister" inputmode="url" value="<?= nc_h($form['konzertmeister']) ?>" placeholder="https://rest.konzertmeister.app/…">
      <small>Link aus Konzertmeister › Webseiten-Einbindung. Leer lassen, wenn ihr Konzertmeister nicht nutzt.</small>
    </label>
    <?php
}
?>
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Notencloud einrichten</title>
<style>
  :root { color-scheme: dark; --bg:#121316; --card:#1b1d22; --line:#2c2f37; --text:#f1f3f6; --muted:#9aa1ad; --accent:#38bdf8; --ok:#34d399; --bad:#f87171; }
  * { box-sizing: border-box; }
  body { margin:0; background:var(--bg); color:var(--text); font:16px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 640px; margin: 0 auto; padding: 32px 16px 64px; }
  h1 { font-size: 26px; margin: 0 0 4px; letter-spacing: -.01em; }
  h2 { font-size: 18px; margin: 0 0 12px; }
  p { margin: 0 0 12px; }
  .lead { color: var(--muted); margin-bottom: 24px; }
  section { background: var(--card); border: 1px solid var(--line); border-radius: 16px; padding: 20px; margin-bottom: 16px; }
  label { display:block; font-weight:600; margin-bottom: 16px; }
  label em { font-weight: 400; color: var(--muted); font-style: normal; }
  input { display:block; width:100%; margin-top:6px; padding: 11px 12px; border-radius: 10px; border: 1px solid var(--line); background: #0f1013; color: var(--text); font: inherit; }
  input:focus-visible, button:focus-visible, a:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  label.check { display:flex; gap:10px; align-items:flex-start; font-weight:400; }
  label.check input { width:auto; margin-top:5px; flex:none; }
  small { display:block; font-weight:400; color: var(--muted); margin-top: 4px; }
  button, .button { display:inline-block; border:0; border-radius: 10px; padding: 12px 20px; background: var(--accent); color:#06202c; font: inherit; font-weight: 700; cursor: pointer; text-decoration:none; }
  button.plain { background: transparent; color: var(--muted); border: 1px solid var(--line); font-weight: 500; }
  button[disabled] { opacity:.5; cursor: not-allowed; }
  ul.checks { list-style:none; padding:0; margin:0; }
  ul.checks li { padding: 4px 0 4px 28px; position: relative; }
  ul.checks li::before { position:absolute; left:0; font-weight:700; }
  ul.checks li.ok::before { content:"✓"; color: var(--ok); }
  ul.checks li.bad::before { content:"✗"; color: var(--bad); }
  .msg { border-radius: 12px; padding: 12px 16px; margin-bottom: 16px; }
  .msg.error { background: #3a1719; border: 1px solid #7f2a2e; }
  .msg.notice { background: #10301f; border: 1px solid #1f6b46; }
  code, .copy { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; font-size: 14px; overflow-wrap: anywhere; }
  .copy { display:block; background:#0f1013; border:1px solid var(--line); border-radius:10px; padding:10px 12px; margin: 6px 0 12px; user-select: all; }
  ol { padding-left: 20px; margin: 0; }
  ol li { margin-bottom: 8px; }
  .row { display:flex; gap:12px; flex-wrap:wrap; align-items:center; }
  a { color: var(--accent); }
</style>
</head>
<body>
<main>
  <h1>Notencloud</h1>
  <p class="lead"><?= $view === 'install' ? 'Einrichtung für euren Verein' : ($view === 'done' ? 'Fertig eingerichtet' : 'Verwaltung') ?></p>

  <?php if ($error !== ''): ?><div class="msg error" role="alert"><?= nc_h($error) ?></div><?php endif; ?>
  <?php if ($notice !== ''): ?><div class="msg notice" role="status"><?= nc_h($notice) ?></div><?php endif; ?>

  <?php if ($view === 'install'): ?>
    <section>
      <h2>1. Voraussetzungen</h2>
      <ul class="checks">
        <?php foreach ($requirements as [$label, $ok, $help]): ?>
          <li class="<?= $ok ? 'ok' : 'bad' ?>"><?= nc_h($label) ?><?php if (!$ok): ?><small><?= nc_h($help) ?></small><?php endif; ?></li>
        <?php endforeach; ?>
      </ul>
    </section>
    <section>
      <h2>Wo wird eingerichtet?</h2>
      <p>Die App wird in genau diesen Ordner entpackt und ist danach hier erreichbar:</p>
      <span class="copy"><?= nc_h($appUrl) ?></span>
      <?php if ($foreign === []): ?>
        <p>Der Ordner ist leer – so soll es sein. Stimmt die Adresse nicht, <code>install.php</code> in den Ordner der gewünschten (Sub-)Domain verschieben.</p>
      <?php else: ?>
        <div class="msg error" role="alert">
          <strong>Achtung: In diesem Ordner liegen schon Dateien.</strong>
          Liegt hier eure Vereins-Webseite, würde sie überschrieben (unter anderem <code>index.html</code> und <code>.htaccess</code>).
          Legt für Notencloud eine eigene Subdomain oder einen eigenen Unterordner an und ladet <code>install.php</code> dorthin.
          <small>Gefunden: <?= nc_h(implode(', ', array_slice($foreign, 0, 8))) ?><?= count($foreign) > 8 ? ' und ' . (count($foreign) - 8) . ' weitere' : '' ?></small>
        </div>
      <?php endif; ?>
    </section>
    <form method="post" autocomplete="off">
      <input type="hidden" name="token" value="<?= nc_h($token) ?>">
      <input type="hidden" name="action" value="install">
      <section>
        <h2>2. Euer Verein</h2>
        <?php nc_fields($form); ?>
      </section>
      <section>
        <h2>3. Passwort für diese Seite</h2>
        <label>Passwort
          <input type="password" name="password" required minlength="10" autocomplete="new-password">
          <small>Mindestens 10 Zeichen. Damit ruft ihr diese Seite später wieder auf, um die App zu aktualisieren. Es ist <strong>nicht</strong> das Nextcloud-Passwort.</small>
        </label>
        <?php if ($foreign !== []): ?>
          <label class="check"><input type="checkbox" name="overwrite" value="ja">
            <span>Ich habe geprüft: In diesem Ordner liegt keine Webseite, die erhalten bleiben muss. Vorhandene Dateien dürfen überschrieben werden.</span></label>
        <?php endif; ?>
        <button type="submit" <?= $ready ? '' : 'disabled' ?>>Notencloud einrichten</button>
        <small>Lädt die App (etwa 17 MB) und richtet sie in diesem Ordner ein. Das dauert bis zu einer Minute.</small>
      </section>
    </form>

  <?php elseif ($view === 'done'): ?>
    <section>
      <h2>Die App läuft</h2>
      <p>Fassung <?= nc_h($state['version'] ?? '') ?> ist eingerichtet. Unter dieser Adresse erreichen sie eure Mitglieder:</p>
      <span class="copy"><?= nc_h($appUrl) ?></span>
      <a class="button" href="./">Notencloud öffnen</a>
    </section>
    <section>
      <h2>So geht es weiter</h2>
      <ol>
        <li>Öffnet die App und meldet euch mit einem Nextcloud-Konto an („Im Browser anmelden“).</li>
        <li>Schickt die Adresse oben an eure Mitglieder. Auf iPad und iPhone: in Safari öffnen, dann <em>Teilen › Zum Home-Bildschirm</em>.</li>
        <li>Für die Android-App verbindet dieser Link die App mit eurer Nextcloud:
          <span class="copy"><?= nc_h($setupLink) ?></span></li>
        <li>Für Updates ruft ihr später wieder <code>install.php</code> auf und meldet euch mit dem eben vergebenen Passwort an.</li>
      </ol>
    </section>

  <?php elseif ($view === 'login'): ?>
    <form method="post">
      <input type="hidden" name="token" value="<?= nc_h($token) ?>">
      <input type="hidden" name="action" value="login">
      <section>
        <h2>Anmelden</h2>
        <label>Passwort der Einrichtung
          <input type="password" name="password" required autofocus autocomplete="current-password">
          <small>Das Passwort, das bei der Einrichtung vergeben wurde. Vergessen? Dann die Datei <code><?= NC_STATE_FILE ?></code> auf dem Webhosting löschen und diese Seite neu laden.</small>
        </label>
        <button type="submit">Anmelden</button>
      </section>
    </form>

  <?php else: ?>
    <section>
      <h2>App-Fassung</h2>
      <p>Installiert: <strong><?= nc_h($state['version'] ?? 'unbekannt') ?></strong>
        <?php if ($latest !== null): ?>
          · Neueste: <strong><?= nc_h($latest['version']) ?></strong>
          <?= ($latest['version'] === ($state['version'] ?? '')) ? '– ihr seid aktuell.' : '' ?>
        <?php endif; ?>
      </p>
      <form method="post" class="row">
        <input type="hidden" name="token" value="<?= nc_h($token) ?>">
        <input type="hidden" name="action" value="update">
        <button type="submit">Auf die neueste Fassung aktualisieren</button>
      </form>
      <small>Eure Einstellungen und die Noten in der Nextcloud bleiben unberührt.</small>
    </section>
    <form method="post" autocomplete="off">
      <input type="hidden" name="token" value="<?= nc_h($token) ?>">
      <input type="hidden" name="action" value="settings">
      <section>
        <h2>Einstellungen</h2>
        <?php nc_fields($form); ?>
        <button type="submit">Einstellungen speichern</button>
      </section>
    </form>
    <section>
      <h2>Für eure Mitglieder</h2>
      <p>Adresse der App:</p>
      <span class="copy"><?= nc_h($appUrl) ?></span>
      <p>Einrichtungs-Link für die Android-App:</p>
      <span class="copy"><?= nc_h($setupLink) ?></span>
      <form method="post">
        <input type="hidden" name="token" value="<?= nc_h($token) ?>">
        <input type="hidden" name="action" value="logout">
        <button type="submit" class="plain">Abmelden</button>
      </form>
    </section>
  <?php endif; ?>
</main>
</body>
</html>
