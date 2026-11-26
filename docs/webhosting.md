# Notencloud für den eigenen Verein einrichten

Diese Anleitung richtet Notencloud für einen Verein auf **einfachem Webhosting mit PHP**
ein – ohne eigenen Server, ohne SSH, ohne etwas zu bauen. Beschrieben ist der Weg mit
Hetzner (Webhosting + Storage Share); er funktioniert genauso mit jedem anderen
PHP-Webhosting und jeder anderen Nextcloud.

Dauer: etwa 30 Minuten, davon 2 Minuten für die App selbst.

## Was man braucht

| Baustein | Wofür | Beispiel Hetzner |
|---|---|---|
| **Nextcloud** | Hier liegen Noten, Setlisten und Notizen. Jedes Mitglied hat ein Konto. | Storage Share (z. B. 1 TB) |
| **Webhosting mit PHP** | Liefert die App aus und vermittelt zwischen Browser und Nextcloud (`proxy.php`). | Webhosting, kleinster Tarif |
| **Domain** | Adresse der App, z. B. `noten.euer-verein.de` | zum Webhosting gebucht |

Das Webhosting speichert **keine Noten** – die App belegt rund 45 MB. Der kleinste
Tarif reicht deshalb. Voraussetzungen, die `install.php` selbst prüft:
PHP ab 7.4 mit `curl`, ein beschreibbarer Ordner und ein SSL-Zertifikat (https).

```text
 iPad / Handy / PC                  Webhosting (PHP)                 Storage Share
┌─────────────────┐   https    ┌──────────────────────┐   https   ┌──────────────┐
│ Notencloud-App  │ ─────────▶ │ App-Dateien          │           │  Nextcloud   │
│ (Browser, PWA)  │ ─────────▶ │ proxy.php ───────────┼─────────▶ │  Noten,      │
└─────────────────┘            │ config.json          │           │  Setlisten   │
                               └──────────────────────┘           └──────────────┘
 Android-App ────────────────── direkt, ohne Webhosting ─────────────────▲
```

Der Umweg über `proxy.php` ist nötig, weil eine Nextcloud bei Storage Share fremden
Webseiten den Zugriff aus dem Browser nicht erlaubt (CORS). Die Android-App spricht
direkt mit der Nextcloud und braucht das Webhosting nicht.

## Schritt 1 – Nextcloud vorbereiten

Das macht einmalig die Person, die die Nextcloud verwaltet. **Die App legt diese
Freigaben nicht selbst an** – sie arbeitet mit den Rechten des angemeldeten Kontos und
kann nichts für andere freigeben.

1. **Konten anlegen** – für jedes Mitglied eines (Benutzer › Neues Konto).
2. **Gruppe anlegen**, z. B. `Musiker`, und alle Mitglieder hineinlegen.
   Wer Noten pflegt, kommt zusätzlich in eine Gruppe `Notenwarte`.
3. **Zwei Ordner anlegen** – im Konto der Verwaltung, auf oberster Ebene:

   | Ordner | Freigeben für | Rechte |
   |---|---|---|
   | `Noten` | Gruppe `Musiker` | nur lesen (Gruppe `Notenwarte`: bearbeiten) |
   | `_Setlisten` | Gruppe `Musiker` | bearbeiten, erstellen, löschen |

   Freigeben: Ordner › Teilen-Symbol › Gruppenname eintippen › Rechte wählen.
   Bei allen Mitgliedern erscheinen beide Ordner dann automatisch auf oberster Ebene.
4. **Noten hochladen** – ein Ordner je Stück, darin eine PDF je Stimme
   (Aufbau siehe [README](../README.md#-empfohlene-ordnerstruktur-auf-nextcloud)).
   Wer einen Notenschrank einscannt: [digitalisieren-mit-claude.md](digitalisieren-mit-claude.md)
   beschreibt, wie Claude Stapel-Scans in Einzelstimmen teilt und richtig benennt.

Wichtig ist die Reihenfolge: **erst freigeben, dann die Mitglieder einladen.** Meldet
sich jemand an, bevor `_Setlisten` freigegeben ist, legt die App beim ersten Speichern
einen eigenen, privaten Ordner `_Setlisten` in dessen Konto an. Die spätere Freigabe
heißt dort dann `_Setlisten (2)` und wird von der App nicht gefunden. Abhilfe: Das
Mitglied löscht seinen privaten Ordner und benennt die Freigabe in `_Setlisten` um.

Was wo landet:

| Inhalt | Ort | Wer sieht es |
|---|---|---|
| Noten | `Noten/…` | alle |
| Setlisten | `_Setlisten/` | alle |
| Vereinsdatei `club_config.json` (z. B. Konzertmeister-Link) | `_Setlisten/` – entsteht, sobald jemand mit Schreibrecht den Kalender in der App einstellt | alle, auch die Android-App |
| Notizen in den Noten | `Noten/_Notizen/<Konto>/`, bei schreibgeschütztem Notenordner `_Notizen/<Konto>/` im eigenen Bereich | nur das Mitglied (auf all seinen Geräten) |

## Schritt 2 – Webhosting vorbereiten

Notencloud braucht einen **eigenen, leeren Ordner** mit eigener Adresse. Das muss
stehen, bevor `install.php` hochgeladen wird.

> **Nicht in den Ordner der Vereins-Webseite installieren.** Die Einrichtung entpackt
> die App in den Ordner, in dem `install.php` liegt, und würde dort unter anderem
> `index.html` und `.htaccess` ersetzen. `install.php` warnt, wenn der Ordner nicht leer
> ist, und richtet dann nur nach ausdrücklicher Bestätigung ein.

### Läuft auf dem Webhosting schon die Vereins-Webseite?

Das ist kein Hindernis – beides läuft nebeneinander auf demselben Paket:

```text
public_html/              ← Vereins-Webseite   → https://euer-verein.de
public_html/noten/        ← Notencloud         → https://noten.euer-verein.de
```

Die Subdomain bekommt **keine eigene IP**. Sie zeigt auf denselben Server wie die
Vereins-Webseite; der Webserver erkennt am Namen in der Adresse, welchen Ordner er
ausliefert.

### So geht es (Hetzner konsoleH)

Die Menünamen stammen aus der Hetzner-Dokumentation und können sich ändern; bei
anderen Anbietern heißen die Punkte ähnlich.

1. **Subdomain anlegen:** In konsoleH die Domain auswählen › *Einstellungen* ›
   *Subdomains* › neue Subdomain `noten`. Als Verzeichnis einen **eigenen Ordner**
   angeben, z. B. `public_html/noten` (nicht `public_html` selbst – dort liegt die
   Vereins-Webseite).
2. **DNS prüfen** – je nachdem, wo die Domain liegt:

   | Wo liegt die Domain? | Was ist zu tun? |
   |---|---|
   | Bei Hetzner, zum selben Webhosting gebucht | In der Regel nichts: Die Subdomain ist über das Webhosting erreichbar. Zur Kontrolle unter *DNS* nachsehen, ob es einen Eintrag für `noten` gibt (oder einen Platzhalter-Eintrag `*`). |
   | Bei einem anderen Anbieter | Dort einen DNS-Eintrag für `noten` anlegen. Am einfachsten **CNAME** `noten` → `euer-verein.de.` Alternativ ein **A-Eintrag** `noten` mit **derselben IP**, die schon für die Hauptdomain eingetragen ist. |

   Bis ein neuer Eintrag überall bekannt ist, kann es von ein paar Minuten bis zu
   einigen Stunden dauern.
3. **SSL-Zertifikat:** *SSL Manager* › *SSL-Accounts* › bei `noten.euer-verein.de` ein
   kostenloses **Let’s-Encrypt-Zertifikat** beantragen. Die Subdomain erscheint dort
   erst, nachdem sie angelegt wurde. Danach *HTTPS-Weiterleitung* auf **Ein** stellen.
4. **PHP-Version:** eine aktuelle wählen (8.x).
5. **Probe:** `https://noten.euer-verein.de` im Browser öffnen.

   | Was erscheint | Bedeutung |
   |---|---|
   | leere Seite, Ordnerliste, „403“ oder Platzhalterseite des Anbieters | richtig – weiter mit Schritt 3 |
   | die Vereins-Webseite | Die Subdomain zeigt auf den falschen Ordner – in Punkt 1 den eigenen Ordner zuweisen. |
   | Zertifikatswarnung | Das Zertifikat ist noch nicht ausgestellt – etwas warten (Punkt 3). |
   | „Seite nicht gefunden“ / keine Verbindung | Der DNS-Eintrag fehlt oder ist noch nicht überall bekannt (Punkt 2). |

### Ohne Subdomain

Wer sich DNS und Zertifikat sparen will, legt nur den Ordner `public_html/noten` an und
lädt `install.php` dorthin. Die App läuft dann unter `https://euer-verein.de/noten/`
und nutzt das Zertifikat der Hauptseite.

Haken: Systeme wie WordPress leiten über ihre eigene `.htaccess` unbekannte Adressen auf
sich um und können `/noten/` abfangen. Zeigt `https://euer-verein.de/noten/install.php`
eine Seite der Vereins-Webseite statt der Einrichtung, ist das der Fall – dann die
Subdomain nehmen.

### Eigene Adresse auch für die Nextcloud (freiwillig)

Ein Storage Share ist unter einer Adresse wie `nx12345.your-storageshare.de` erreichbar.
Wer lieber `cloud.euer-verein.de` hätte, legt dafür einen CNAME auf die Storage-Share-
Adresse an und trägt die Domain in den Einstellungen des Storage Share ein (Hetzner-
Dokumentation: „Storage Share › Subdomains“). Für Notencloud ist das nicht nötig – wenn,
dann **vor** der Einrichtung erledigen und in `install.php` die neue Adresse eintragen.

## Schritt 3 – App einrichten

1. [`install.php`](https://github.com/Mindstorms123/notencloud/releases/latest/download/install.php)
   herunterladen.
2. Per WebFTP (oder FTP) in den **leeren Ordner der Subdomain** aus Schritt 2 hochladen.
3. Im Browser öffnen: `https://noten.euer-verein.de/install.php`
   Die Seite zeigt oben, unter welcher Adresse die App landen wird, und ob der Ordner leer ist.
4. Formular ausfüllen:
   - **Name des Vereins** – steht auf Ablaufplänen und in Einladungen
   - **Adresse der Nextcloud** – z. B. `https://nx12345.your-storageshare.de`
   - **Notenordner** – `/Noten`, wenn ihr Schritt 1 gefolgt seid
   - **Konzertmeister-Kalender** – freiwillig
   - **Passwort** – für spätere Updates; *nicht* das Nextcloud-Passwort
5. **„Notencloud einrichten“** – das Skript lädt die App, entpackt sie und schreibt
   die Einstellungen. Danach zeigt es die Adresse für eure Mitglieder.

Falls das Webhosting nichts aus dem Internet laden darf: `notencloud-web.zip` von der
[Release-Seite](https://github.com/Mindstorms123/notencloud/releases/latest) laden und
neben `install.php` hochladen – das Skript nimmt dann dieses Archiv.

## Schritt 4 – Mitglieder einladen

- **iPad / iPhone:** Adresse in Safari öffnen › *Teilen* › *Zum Home-Bildschirm*.
  Danach startet Notencloud wie eine App, auch ohne Internet.
- **Android:** die App aus den
  [Releases](https://github.com/Mindstorms123/notencloud/releases/latest) installieren
  und den Einrichtungs-Link antippen, den `install.php` anzeigt
  (`notencloud://setup?server=…`). Alternativ geht auch die Web-Adresse in Chrome.
- **PC / Mac:** Adresse im Browser öffnen.

Anmelden: **„Im Browser anmelden“** und die Zugangsdaten des Nextcloud-Kontos eingeben.

## Aktualisieren und Einstellungen ändern

`https://noten.euer-verein.de/install.php` erneut öffnen und mit dem Passwort der
Einrichtung anmelden:

- **Auf die neueste Fassung aktualisieren** – lädt das aktuelle Release. Einstellungen
  und Noten bleiben unberührt. Auf den Geräten kommt die neue Fassung beim nächsten
  Öffnen an.
- **Einstellungen** – Vereinsname, Nextcloud-Adresse, Notenordner, Kalender.

Passwort vergessen: `install.config.php` auf dem Webhosting löschen und die Seite neu
laden – die Einrichtung startet dann von vorn (die App-Dateien werden überschrieben,
die Noten liegen ohnehin in der Nextcloud).

## Dateien auf dem Webhosting

| Datei | Inhalt | Bei Updates |
|---|---|---|
| `index.html`, `main.dart.js`, `assets/`, `canvaskit/`, `sw.js` … | die App | wird ersetzt |
| `proxy.php` | Vermittler zur Nextcloud | wird ersetzt |
| `install.php` | Einrichtung und Updates | wird ersetzt |
| `config.json` | Vereinsname, Nextcloud-Adresse, Notenordner, Kalender | bleibt |
| `proxy.config.php` | welche Server der Proxy ansprechen darf | bleibt |
| `install.config.php` | Passwort (als Hash), installierte Fassung | bleibt |

`config.json` von Hand:

```json
{
  "club": "Musikverein Beispielstadt",
  "server": "https://nx12345.your-storageshare.de",
  "folder": "/Noten",
  "konzertmeister": ""
}
```

## Sicherheit

- Zugangsdaten liegen **nicht** auf dem Webhosting. Die App meldet sich über die
  Nextcloud an und bewahrt ein App-Passwort nur auf dem jeweiligen Gerät auf.
  Es lässt sich in der Nextcloud unter *Einstellungen › Sicherheit* jederzeit widerrufen.
- Jede Anfrage der Web-App läuft über `proxy.php` und damit über das Webhosting. Wer
  das Webhosting verwaltet, könnte den Verkehr mitlesen – es gehört deshalb in die
  Hand des Vereins.
- `proxy.config.php` beschränkt den Proxy auf die eigene Nextcloud. **Ohne diese Datei
  leitet `proxy.php` an jeden Server weiter** – wer die App von Hand entpackt statt
  über `install.php`, muss sie selbst anlegen.

## Wenn etwas nicht klappt

| Anzeige | Ursache und Abhilfe |
|---|---|
| „In diesem Ordner liegen schon Dateien“ | `install.php` liegt im Ordner einer bestehenden Webseite oder der Anbieter hat eine Platzhalterseite abgelegt. Im ersten Fall `install.php` in einen eigenen Ordner verschieben; im zweiten die Bestätigung ankreuzen. |
| Die Subdomain zeigt die Vereins-Webseite | Der Subdomain ist kein eigener Ordner zugewiesen – im Kundenmenü nachholen (Schritt 2). |
| Zertifikatswarnung im Browser | SSL für die Subdomain ist noch nicht aktiv oder die Adresse noch nicht überall bekannt – etwas warten, dann im Kundenmenü erneut einschalten. |
| `install.php` zeigt Text statt einer Seite | PHP ist für die Domain nicht aktiv – im Kundenmenü einschalten. |
| „Unter … antwortet keine Nextcloud“ | Adresse stimmt nicht. Nur den vorderen Teil eintragen, z. B. `https://nx12345.your-storageshare.de`. |
| „Im neuesten Release liegt (noch) kein Web-Paket“ | Das Release wurde gerade erst veröffentlicht; das Paket hängt ein paar Minuten später daran. |
| App: „Dieser Server ist für den Proxy nicht freigegeben“ | Die Nextcloud-Adresse wurde geändert – in `install.php` unter *Einstellungen* neu speichern. |
| App: „Diese Seite darf den Proxy nicht nutzen“ | Die App läuft unter einer anderen Adresse als bei der Einrichtung (z. B. neue Domain). `install.php` unter der neuen Adresse öffnen und *Einstellungen speichern*. |
| Setlisten erscheinen nur beim Ersteller | `_Setlisten` ist nicht freigegeben, siehe Schritt 1. |
| Notizen werden nicht hochgeladen | Kein Schreibrecht im Notenordner – die App weicht automatisch in den eigenen Bereich aus; die Meldung nennt den Grund. |
| Nach einem Update läuft noch die alte Fassung | App ganz schließen und neu öffnen. |

## Für Entwickler

- Paket selbst bauen: `scripts/build_web.sh` → `build/notencloud-web.zip`
- Bei jedem veröffentlichten GitHub-Release hängt
  `.github/workflows/release-web.yml` das Paket, `install.php` und `version.json` an.
- Einrichtung und Proxy testen: `test/hosting/run.sh` (braucht nur `php`, `curl`, `python3`)
- Die Web-Fassung auf GitHub Pages (`.github/workflows/pages.yml`) nutzt einen Proxy
  auf einem anderen Server; dessen Adresse kommt beim Bauen über
  `NOTENCLOUD_PROXY_URL` oder zur Laufzeit über `"proxy"` in `config.json`.
