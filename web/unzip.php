<?php
/**
 * Notencloud WebFTP Unzip Helper
 * 
 * Entpackt 'notencloud-web.zip' automatisch im aktuellen Verzeichnis
 * für Webhosting-Umgebungen ohne SSH / ohne WebFTP-Entpackfunktion.
 */

header('Content-Type: text/html; charset=utf-8');

$zipFile = __DIR__ . '/notencloud-web.zip';

if (!file_exists($zipFile)) {
    echo "<h2>❌ Datei nicht gefunden: notencloud-web.zip</h2>";
    echo "<p>Bitte lade die Datei <code>notencloud-web.zip</code> per WebFTP in denselben Ordner hoch.</p>";
    exit;
}

if (!class_exists('ZipArchive')) {
    echo "<h2>❌ PHP-Modul ZipArchive ist auf diesem Server nicht aktiviert.</h2>";
    exit;
}

$zip = new ZipArchive;
$res = $zip->open($zipFile);

if ($res === TRUE) {
    $zip->extractTo(__DIR__);
    $zip->close();
    
    // Bereinigung: zip und unzip.php nach erfolgreichem Entpacken löschen
    @unlink($zipFile);
    @unlink(__FILE__);
    
    echo "<h2>✅ Notencloud Web PWA erfolgreich entpackt!</h2>";
    echo "<p>Die Dateien wurden entpackt und das Archiv wurde zur Bereinigung gelöscht.</p>";
    echo "<p><a href='./' style='display:inline-block;padding:12px 24px;background:#0284C7;color:white;text-decoration:none;border-radius:8px;font-weight:bold;'>Notencloud jetzt öffnen</a></p>";
} else {
    echo "<h2>❌ Fehler beim Entpacken der ZIP-Datei (Code: $res)</h2>";
}
