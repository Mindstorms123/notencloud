# Noten digitalisieren mit Claude

Einen Notenschrank einzuscannen ist Fleißarbeit: Stapel in den Einzugsscanner, und dann
müssen aus einer langen PDF hundert richtig benannte Einzelstimmen werden. Diesen zweiten
Teil kann [Claude](https://claude.ai) übernehmen. Diese Seite enthält die Prompts dafür –
zum Kopieren.

Claude kann sich verlesen. Deshalb ist jeder Ablauf hier so gebaut, dass Claude **erst
einen Plan zeigt** und nur schreibt, was ihr bestätigt habt – und nie etwas löscht.

## Was Notencloud erwartet

```text
Noten/                                 ← Notenordner (für alle freigegeben)
├── 01_Aktuelle Noten/                 ← Kategorie
│   └── Alte Kameraden/                ← ein Ordner je Stück
│       ├── Partitur.pdf               ← eine PDF je Stimme
│       ├── Flöte 1.pdf
│       ├── Klarinette 2 in B.pdf
│       └── Trompete 1-2 in B.pdf      ← Kombistimme
└── 02_Archiv/
_Setlisten/                            ← daneben, ebenfalls freigegeben
```

Dateinamen: **`Instrument Stimme in Stimmung.pdf`**

| Teil | Regel | Beispiele |
|---|---|---|
| Instrument | ausgeschrieben, deutsch oder englisch | `Flöte`, `Klarinette`, `Altsaxophon`, `Trompete`, `Flügelhorn`, `Horn`, `Posaune`, `Tenorhorn`, `Bariton`, `Tuba`, `Schlagzeug`, `Pauken`, `Mallets` |
| Stimme | Ziffer; Kombistimmen mit Bindestrich | `1`, `2`, `1-2`, `3-4` |
| Stimmung | nur wenn sie auf dem Blatt steht | `in B`, `in Es`, `in F`, `in C` |
| Sonderfälle | | `Partitur.pdf`, `Direktion in C.pdf` |

Ordnernamen dürfen eine Nummer vorn tragen (`01_…`), die App blendet sie aus. Ordner,
die mit `_` oder `.` beginnen, sind für die App reserviert bzw. unsichtbar.

## So kommt Claude an die Nextcloud

**Empfohlen – über den synchronisierten Ordner.** Auf dem Rechner den
[Nextcloud-Desktop-Client](https://nextcloud.com/install/#install-clients) einrichten;
er hält den Ordner `Noten` als ganz normalen Ordner auf der Festplatte aktuell. Claude
arbeitet dann einfach in diesem Ordner – ohne Passwort, und der Client lädt alles hoch.
Dafür braucht es ein Claude, das auf Ordner des Rechners zugreifen darf: die
Claude-Desktop-App oder Claude Code.

**Ohne Installation – über den Chat.** Scan im Chat auf claude.ai hochladen, Claude teilt
ihn und gibt eine ZIP-Datei zurück; die zieht ihr im Browser in die Nextcloud. Geht für
einzelne Stücke, wird bei einem ganzen Schrank mühsam.

**Direkt per WebDAV.** Möglich, aber dann bekommt Claude Zugangsdaten. Wenn überhaupt:
in der Nextcloud unter *Einstellungen › Sicherheit* ein eigenes **App-Passwort** anlegen,
nie das echte Passwort, und es danach wieder löschen.

Die Prompts unten gehen vom ersten Weg aus. Die Pfade in `‹spitzen Klammern›` ersetzt ihr.

## Scannen

- **300 dpi, Graustufen** (schwarz-weiß nur bei sauberen Drucken), beidseitig, als PDF.
- **Ein Stück = ein Stapel = eine PDF** ist am sichersten. Mehrere Stücke in einem Stapel
  gehen auch – Claude erkennt den Wechsel am Titel.
- Reihenfolge im Stapel ist egal, solange die Seiten einer Stimme zusammenliegen.
- Scans in einen Ordner **außerhalb** des Notenordners legen, z. B. `Dokumente/Notenscans`.
  Alles, was im Notenordner liegt, erscheint sofort bei allen in der App.

## Prompt 1 – Ordner anlegen

```text
Ich richte ein Notenarchiv für die App Notencloud ein. Der Notenordner unseres Vereins
ist ‹/Pfad/zu/Nextcloud/Noten› (wird mit unserer Nextcloud synchronisiert).

Lege darin diese Kategorien als Ordner an, falls sie fehlen:
01_Aktuelle Noten, 02_Archiv, 03_Weihnachten, 04_Märsche

Regeln von Notencloud:
- Ebene 1 unter dem Notenordner sind Kategorien, Ebene 2 ist ein Ordner je Stück,
  darin liegt eine PDF je Stimme.
- Keine eigenen Ordner anlegen, die mit "_" oder "." beginnen.

Zeig mir zuerst, was schon da ist und was du anlegen würdest. Lege erst an, wenn ich
zustimme. Lösche und verschiebe nichts.
```

Die beiden Freigaben (`Noten`, `_Setlisten`) richtet ihr selbst in der Nextcloud ein –
siehe [webhosting.md, Schritt 1](webhosting.md#schritt-1--nextcloud-vorbereiten). Das
kann und soll Claude nicht für euch tun.

## Prompt 2 – Stapel-Scans teilen und einsortieren

Vorher einmal [`tools/noten_teilen.py`](../tools/noten_teilen.py) herunterladen und in den
Scan-Ordner legen. Das Skript schneidet die PDF nach einem Plan und prüft, dass jede Seite
genau einmal vergeben ist; Claude muss dadurch nicht selbst an der PDF herumrechnen.

```text
Im Ordner ‹/Pfad/zu/Notenscans› liegen Stapel-Scans von Blasorchester-Noten als PDF
(Einzugsscanner, mehrere Stimmen hintereinander) und das Skript noten_teilen.py.
Der Notenordner unseres Vereins ist ‹/Pfad/zu/Nextcloud/Noten›.

Aufgabe: Jeden Scan in Einzelstimmen teilen und im Notenordner ablegen unter
‹Kategorie›/‹Titel des Stücks›/‹Instrument Stimme in Stimmung›.pdf

Geh für jede Scan-Datei so vor:

1. Sieh dir JEDE Seite an (bei langen Scans in Abschnitten von 20 Seiten). Lies oben auf
   der Seite Titel und Stimmenbezeichnung ab. Notiere je Seite: Titel, Stimme,
   erste Seite oder Folgeseite einer Stimme, leer, auf dem Kopf.
   Rate nicht: Was du nicht sicher lesen kannst, markierst du als "unsicher".

2. Benenne die Stimmen nach diesen Regeln:
   - Instrument ausgeschrieben auf Deutsch: Flöte, Piccolo, Oboe, Fagott, Es-Klarinette,
     Klarinette, Bassklarinette, Sopransaxophon, Altsaxophon, Tenorsaxophon,
     Baritonsaxophon, Trompete, Flügelhorn, Kornett, Horn, Posaune, Tenorhorn, Bariton,
     Euphonium, Tuba, Schlagzeug, Pauken, Mallets, Partitur, Direktion
   - danach die Stimmennummer als Ziffer (1, 2, 3); Kombistimmen "1-2" oder "3-4"
   - danach die Stimmung, wenn sie auf dem Blatt steht: "in B", "in Es", "in F", "in C"
   - Beispiele: "Klarinette 2 in B.pdf", "Trompete 1-2 in B.pdf", "Horn 3 in F.pdf",
     "Posaune 1 in C.pdf", "Tuba in C.pdf", "Schlagzeug.pdf", "Partitur.pdf",
     "Direktion in C.pdf"
   - Englische Bezeichnungen übersetzen (1st Bb Clarinet → Klarinette 1 in B).
   - Gibt es dieselbe Stimme in zwei Stimmungen, bekommen beide ihre Stimmung in den Namen.

3. Schreibe einen Plan als JSON neben den Scan (gleicher Name, Endung .plan.json) in dem
   Format, das oben in noten_teilen.py beschrieben ist. Leere Rückseiten kommen in
   "leerseiten". Auf dem Kopf stehende Stimmen bekommen "drehen": 180.

4. Prüfe den Plan:  python3 noten_teilen.py pruefen ‹Plan›
   (Falls pypdf fehlt: pip install pypdf.) Behebe gemeldete Fehler.

5. Zeig mir den Plan als Tabelle: Stück | Datei | Seiten | Anmerkung. Führe alles auf,
   was du als unsicher markiert hast, und nenne Stimmen, die bei dieser Besetzung zu
   erwarten wären, aber fehlen. Frag mich nach der Kategorie, wenn sie nicht klar ist.
   WARTE auf meine Bestätigung.

6. Erst danach:  python3 noten_teilen.py teilen ‹Plan› --ziel ‹Notenordner›
   Verschiebe den Scan samt Plan anschließend nach ‹/Pfad/zu/Notenscans›/erledigt.

Grundsätze: Im Notenordner nichts löschen, nichts überschreiben, nichts umbenennen, was
schon da ist. Existiert ein Stück schon, sag es mir, statt es zu ergänzen.
Fang mit der ersten Datei an und mach nach jeder Datei eine Pause, bis ich "weiter" sage.
```

Sobald die ersten zwei, drei Stücke sauber durchgelaufen sind, könnt ihr die Pause nach
jeder Datei aus dem Prompt streichen und Claude eine ganze Reihe abarbeiten lassen –
die Bestätigung des Plans (Schritt 5) sollte bleiben.

## Prompt 3 – Vorhandenes Archiv aufräumen

Für Vereine, die schon PDFs haben, aber mit wild gewachsenen Namen.

```text
Der Ordner ‹/Pfad/zu/Nextcloud/Noten› ist das Notenarchiv unseres Vereins für die App
Notencloud. Es ist über Jahre gewachsen. Ich möchte es in diese Form bringen:
‹Kategorie›/‹Stück›/‹Instrument Stimme in Stimmung›.pdf

1. Verschaff dir einen Überblick: Ordnertiefe, Zahl der Stücke und PDFs, typische
   Namensmuster. Öffne noch keine PDFs.
2. Erstelle eine Liste "alt → neu" als CSV-Datei außerhalb des Notenordners. Nimm nur
   Änderungen auf, die nötig sind:
   - Stücke, die nicht in einem Kategorie-Ordner liegen
   - PDFs, die direkt in einer Kategorie liegen statt in einem Stück-Ordner
   - Dateinamen ohne erkennbares Instrument oder ohne Stimmennummer
   - eine PDF mit mehreren Stimmen (als "muss geteilt werden" markieren, nicht anfassen)
   Namensregeln: Instrument ausgeschrieben, Stimmennummer als Ziffer, Kombistimmen "1-2",
   Stimmung "in B / in Es / in F / in C" nur wenn bekannt. Beispiel: "Klarinette 2 in B.pdf".
   Wenn der Name nichts hergibt, sieh in die erste Seite der PDF.
3. Zeig mir eine Zusammenfassung und die zwanzig auffälligsten Fälle. WARTE auf mein Okay.
4. Benenne dann nur um bzw. verschiebe – nichts löschen, nichts überschreiben. Bei einem
   Namenskonflikt die Datei auslassen und melden. Arbeite Kategorie für Kategorie.

Die Ordner _Setlisten und _Notizen und alles, was mit "_" oder "." beginnt, rührst du
nicht an.
```

Hinweis: Notizen der Mitglieder hängen an Stück und Stimme. Wird eine Datei umbenannt,
findet die App alte Eintragungen dazu nicht mehr. Räumt deshalb auf, **bevor** die
Mitglieder anfangen, in den Noten zu schreiben.

## Kontrolle in der App

Unter *Einstellungen › Digitalisierungs-Check* zeigt Notencloud je Stück, welche Stimmen
der üblichen Besetzung fehlen, und exportiert die Liste als PDF für den Notenwart. Nach
einem Scan-Abend ist das die schnellste Gegenprobe.

## Grenzen

- **Handschriftliche oder blasse Stimmenbezeichnungen** liest Claude unzuverlässig. Diese
  Seiten landen in der Liste „unsicher“ – dort entscheidet ihr.
- **Sehr lange Scans** (über 100 Seiten) besser in mehrere Stapel teilen; je kürzer der
  Scan, desto weniger Verwechslungen.
- **Schiefe Seiten und Ränder** korrigiert das Skript nicht. Das erledigt die
  Scanner-Software besser (automatisch gerade richten, Leerseiten nicht entfernen –
  sonst stimmen Vorder- und Rückseiten nicht mehr).
- **Urheberrecht:** Noten dürfen in Deutschland in der Regel nur mit Erlaubnis des
  Verlags kopiert und digital verteilt werden. Klärt das für euer Repertoire, bevor ihr
  das Archiv für alle freigebt.
