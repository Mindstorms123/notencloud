# Notencloud 🎵

Eine moderne, native Noten-App für Android und iOS mit nahtloser **Nextcloud-Synchronisation**, **Apple Pencil & Stylus-Stiftunterstützung** (inkl. Palm Rejection) und **automatischem Stimmen-Filter**.

---

## 🌟 Kernfunktionen

1. **Nextcloud-Integration (WebDAV):**
   - Direkte Anbindung an die Orchester-Nextcloud (Basic Auth / App-Token).
   - Scannen des Repertoires und automatisches Herunterladen von Einzelstimmen-PDFs.
   - **Offline-First:** Alle Noten und Setlisten werden lokal gecacht, sodass bei Auftritten kein Internetzugang nötig ist.
   - "Bühnen-Download"-Funktion zum Vorladen aller Stimmen mit einem Klick.

2. **Smart Voice Matching (Automatische Stimmen-Filterung):**
   - Der Musiker wählt in den Einstellungen einmalig sein Profil (z. B. *1. Trompete in B♭* oder *2. Klarinette*).
   - Beim Öffnen eines Stücks oder einer Setlist wählt die App automatisch die passende PDF-Stimme aus.
   - Intelligenter Fallback auf Kombistimmen (z. B. `Trompete_1-2.pdf`).
   - Jederzeit manueller Stimmenwechsel und Partitur-Ansicht über das Menü möglich.

3. **Stifteingabe & Anmerkungen (Stylus & Apple Pencil):**
   - Flüssiges Zeichnen mit Apple Pencil (iPad) und Samsung S-Pen (Android) über Impeller 2D Canvas.
   - **Palm Rejection (Handballenerkennung):** Das Handgelenk kann entspannt auf dem Notenblatt abgelegt werden.
   - Werkzeuge: Bleistift, Dirigenten-Rot, Textmarker (halbtransparent), Radierer, Undo/Redo.
   - **Nicht-destruktive Vektorspeicherung:** Zeichnungen werden als Vektor-JSON lokal pro Seite gespeichert – die Original-PDFs auf der Cloud bleiben unberührt.

4. **Setlisten- & Auftritts-Manager:**
   - Schnelle Erstellung von Setlisten für Konzerte, Proben und Gigs.
   - Drag & Drop zum Sortieren der Stücke und Einfügen von Pausen-Markern.
   - Eigene Notizen pro Stück (z. B. „Ohne Wiederholung“, „Attacca“).
   - **Cloud-Synchronisation:** Hat der Nutzer Schreibrechte auf `_Setlisten/` (z. B. Dirigent/Notenwart), wird die Setlist direkt auf Nextcloud hochgeladen und steht sofort allen Orchestermitgliedern zur Verfügung.

---

## 📁 Guideline: Noten- und Ordnerstruktur auf Nextcloud

Damit die App das Notenarchiv und die Stimmen automatisch fehlerfrei erkennt:

```text
Nextcloud/
└── Notenarchiv/                              <-- Hauptordner in den App-Einstellungen
    │
    ├── _Setlisten/                           <-- Zentraler Ordner für Auftrittslisten (.json)
    │   ├── 2026-12-15_Weihnachtskonzert.json
    │   └── 2027-05-01_Fruehlingskonzert.json
    │
    ├── 001_Alte_Kameraden/                   <-- Ordner pro Musikstück (Nummerierung optional)
    │   ├── Partitur.pdf
    │   ├── Flöte_1.pdf
    │   ├── Flöte_2.pdf
    │   ├── Klarinette_1_Bb.pdf
    │   ├── Altsaxophon_1_Eb.pdf
    │   ├── Trompete_1_Bb.pdf
    │   ├── Trompete_2_Bb.pdf
    │   ├── Posaune_1_C.pdf
    │   └── Tuba_in_C.pdf
    │
    └── 002_Bohemian_Rhapsody/
        ├── Partitur.pdf
        ├── Flöte_1.pdf
        └── Trompete_1_Bb.pdf
```

### Dateibenennung für Einzelstimmen:
`[Instrument]_[Stimme]_[Stimmung/Schlüssel].[pdf]`
* Beispiele:
  * `Trompete_1_Bb.pdf`
  * `Klarinette_2_Bb.pdf`
  * `Altsaxophon_1_Eb.pdf`
  * `Posaune_1_Bass.pdf`
  * `Horn_1-2_in_F.pdf` (Kombistimme)

---

## 🚀 Entwicklung & Bauen

### Auf Linux (Entwicklung & Testen):
```bash
# Tests ausführen
flutter test

# App im Browser testen
flutter run -d chrome

# App auf angeschlossenem Android-Gerät ausführen
flutter run -d android
```

### Auf dem Mac (iOS / iPadOS App bauen):
Da der gesamte Code plattformunabhängig in Flutter geschrieben ist:

1. Projekt auf den Mac kopieren oder per Git klonen:
   ```bash
   git clone <dein-repo-url> notencloud
   cd notencloud
   ```
2. Abhängigkeiten laden:
   ```bash
   flutter pub get
   ```
3. Auf dem iPad starten oder Release-Build erstellen:
   ```bash
   # Direkt auf angeschlossenem iPad starten
   flutter run -d "iPad"

   # Oder Xcode öffnen zum Signieren & Archivieren
   open ios/Runner.xcworkspace
   ```
