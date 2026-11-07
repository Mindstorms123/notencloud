# Notencloud 🎵

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![License: CC BY-NC-SA 4.0](https://img.shields.io/badge/License-CC%20BY--NC--SA%204.0-lightgrey.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20iPadOS-brightgreen)]()

**Notencloud** ist eine moderne, native Open-Source Noten-App für Blasorchester, Chöre und Ensembles. Sie verbindet nahtlose **Nextcloud-Synchronisation (WebDAV)** mit **intelligentem Stimmen-Matching**, **Apple Pencil & Stylus-Stiftunterstützung** sowie **benutzerspezifischer Cloud-Sicherung von Notizen**.

---

## ✨ Features im Überblick

### ☁️ 1. Nahtlose Nextcloud-Integration (WebDAV)
- **1-Klick Browser Login (Login Flow v2):** Anmeldung direkt im Web-Browser ohne manuelle Token-Generierung. Alternativ steht der klassische Login (Passwort/App-Passwort) zur Verfügung.
- **1-Klick Setup-Link:** Bandmitglieder können per Einladungslink (`notencloud://setup?server=...&folder=...`) über das native Teilen-Menü (WhatsApp, E-Mail, AirDrop etc.) in Sekunden eingerichtet werden.
- **100 % Offline-First:** Alle Noten, Setlisten und Anmerkungen werden lokal gecacht. Auf der Bühne und in der Probe ist kein Internetzugang erforderlich.
- **Hintergrund-Delta-Sync:** Prüft beim Start leise im Hintergrund auf Änderungen und lädt neue Stücke automatisch vor.

### 🎷 2. Smart Voice Matching & Orchesterfilter
- **Automatisches Stimmen-Matching:** Einmaliges Profil einstellen (z. B. *1. Trompete in B♭* oder *2. Altsaxophon in Es*). Beim Öffnen eines Stücks wählt die App automatisch das passende Notenblatt.
- **Transparente Ausweichstimmen:** Fehlt eine Einzelstimme, greift die App automatisch auf Kombistimmen (z. B. `Trompete 1-2.pdf`) oder Nachbarstimmen zurück und kennzeichnet dies mit einem bernsteinfarbenen Badge (`Keine 2. St. • Ersatz: Trompete 1.pdf`).
- **Strenge Orchester-Filterung:** Der dynamische Register-Filter zeigt nur echte Orchester-Instrumente an und filtert Ordner- oder Stücknamen zuverlässig heraus.
- **Live-Zwei-Wege-Sync:** Änderungen in den Einstellungen aktualisieren sofort den Filter und die Notenliste in Echtzeit.

### 🥁 3. Percussion-Spezialisierung & 1-Tap Schnellauswahl
- **Einheitliche Percussion-Gruppe:** Sämtliche Schlagwerk-Stimmen (Schlagzeug, Drums, Snare, Pauken, Timpani, Mallets, Glockenspiel, Xylophon, Marimba, Vibraphon, Becken etc.) werden im Register einheitlich als **Percussion** zusammengefasst.
- **1-Tap Schnellauswahl:** Schlagzeuger können direkt in der Notenübersicht mit einem Klick zwischen ihren Rollen umschalten:
  - `[ Alle ]` – Alle Stimmen des Schlagwerks anzeigen
  - `[ Schlagzeug ]` – Schlagzeug, Drumset, Snare, Becken & Percussion
  - `[ Pauken ]` – Pauken / Timpani
  - `[ Mallets ]` – Glockenspiel, Xylophon, Marimba, Vibraphon, Mellods
- Beim Umschalten auf z. B. *Pauken* matchen sofort alle Stücke mit Pauken-Part als Hauptstimme.

### ✍️ 4. Digitale Notizen & Stylus-Unterstützung (Apple Pencil / S-Pen)
- **Flüssiges Zeichnen:** Unterstützt Apple Pencil (iPad) und Samsung S-Pen (Android) mit Handballenerkennung (Palm Rejection).
- **Werkzeuge:** Notizstift (verschiedene Farben), halbtransparenter Textmarker, Radierer, Text-Notizen (z. B. Dirigenten-Rot) sowie Undo/Redo.
- **Nicht-destruktiv:** Die Original-PDFs auf Nextcloud bleiben unangetastet. Notizen werden als Vektordaten gespeichert.
- **Private Nextcloud-Synchronisation:** Notizen werden benutzerspezifisch unter `_Notizen/<Benutzer>/...` gesichert. Jeder Musiker behält seine eigenen Notizen und hat sie auf Tablet und Smartphone stets synchron.

### 📋 5. Setlisten- & Auftritts-Manager
- Erstellung und Verwaltung von Konzert- und Probenprogrammen.
- Drag & Drop zum Umsortieren von Stücken und Einfügen von Pausen-Markern.
- Notizen pro Stück (z. B. *„Ohne Wiederholung“*, *„Attacca“*).
- **Cloud-Synchronisation:** Setlisten werden in `_Setlisten/` synchronisiert und stehen dem gesamten Orchester zur Verfügung.

### 🔍 6. Vollbild & Zoom
- **Doppeltippen-Vollbild:** Ein Doppeltippen auf das Notenblatt schaltet die Leisten aus und maximiert die Noten.
- **Floating Zoom-Kapsel:** Feine Zoomstufen (`[-]`, `[Fit]`, `[+]`) und flüssiges Pinch-to-Zoom mit zwei Fingern.

---

## 📲 Installation

### Android
1. Lade die neueste `app-debug.apk` oder `app-release.apk` aus den [GitHub Releases](https://github.com/Mindstorms123/notencloud/releases) herunter.
2. Öffne die APK auf deinem Android-Gerät (Installation aus unbekannten Quellen erlauben).
3. Öffne die App und melde dich über den Web-Browser bei deiner Nextcloud an.

---

## 🛠️ Bauanleitung (Build Instructions)

### Voraussetzungen
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Version 3.24+ empfohlen)
- Android SDK (für Android-Builds)
- Xcode (auf macOS, für iOS / iPadOS-Builds)

```bash
# Repository klonen
git clone https://github.com/Mindstorms123/notencloud.git
cd notencloud

# Abhängigkeiten installieren
flutter pub get

# Tests ausführen
flutter test
```

---

### 🤖 Android bauen

```bash
# Debug APK bauen:
flutter build apk --debug
# Ausgabepfad: build/app/outputs/flutter-apk/app-debug.apk

# Release APK bauen:
flutter build apk --release
# Ausgabepfad: build/app/outputs/flutter-apk/app-release.apk

# Android App Bundle für Google Play Store:
flutter build appbundle --release
# Ausgabepfad: build/app/outputs/bundle/release/app-release.aab
```

---

### 🍏 iOS / iPadOS bauen & installieren

Für Apple-Geräte (iPhone & iPad) kann Notencloud auf einem Mac gebaut und kostenfrei installiert werden:

#### Methode 1: Direkt über Xcode mit kostenloser Apple ID (Personal Team)
1. Öffne das iOS-Projekt in Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```
2. Schließe dein iPad oder iPhone per USB-Kabel an den Mac an.
3. Wähle in Xcode das Target **Runner** -> Reiter **Signing & Capabilities**.
4. Setze ein Häkchen bei **Automatically manage signing**.
5. Wähle unter **Team** deine persönliche Apple ID aus (hierfür ist **kein** kostenpflichtiges Apple Developer Program erforderlich).
6. Passe gegebenenfalls die Bundle Identifier an (z. B. `de.deinname.notencloud`).
7. Wähle oben als Zielgerät dein iPad/iPhone aus und klicke auf **Run (▶)**.
8. Auf dem iPad: Unter *Einstellungen -> Allgemein -> VPN und Geräteverwaltung* deiner Apple ID vertrauen.

#### Methode 2: IPA erstellen & Sideloading (AltStore / Sideloadly)
1. Erstelle das Release-Paket auf dem Mac:
   ```bash
   flutter build ios --release --no-codesign
   ```
2. Verpacke die erstellte App in eine `.ipa`-Datei:
   ```bash
   mkdir -p Payload
   cp -r build/ios/iphoneos/Runner.app Payload/
   zip -r notencloud.ipa Payload
   rm -rf Payload
   ```
3. Installiere die `notencloud.ipa` über Tools wie **AltStore**, **Sideloadly** oder **LiveContainer** direkt auf deinem iPad.

---

## 📁 Empfohlene Ordnerstruktur auf Nextcloud

Damit Notencloud Stücke und Stimmen optimal erkennt:

```text
Nextcloud/
└── Notenarchiv/                              <-- Hauptordner in den App-Einstellungen
    │
    ├── _Setlisten/                           <-- Zentraler Ordner für Konzertlisten (.json)
    │   ├── 2026-12-15_Weihnachtskonzert.json
    │   └── 2027-05-01_Fruehlingskonzert.json
    │
    ├── _Notizen/                             <-- Benutzerspezifische Notizen & Eintragungen
    │   ├── musiker_anna/
    │   └── musiker_ben/
    │
    ├── 01_Aktuelle Noten/                    <-- Standard-Kategorie
    │   ├── Alte Kameraden/
    │   │   ├── Partitur.pdf
    │   │   ├── Flöte 1.pdf
    │   │   ├── Klarinette 1 in B.pdf
    │   │   ├── Altsaxophon 1 in Es.pdf
    │   │   ├── Trompete 1 in B.pdf
    │   │   ├── Posaune 1 in C.pdf
    │   │   ├── Schlagzeug.pdf
    │   │   └── Pauken.pdf
    │   │
    │   └── Bohemian Rhapsody/
    │       ├── Partitur.pdf
    │       ├── Trompete 1.pdf
    │       └── Mallets.pdf
    │
    └── 02_Archiv/
        └── ...
```

---

## 📄 Lizenz

Dieses Projekt steht unter der **Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License (CC BY-NC-SA 4.0)**.

- **Erlaubt:** Teilen, Kopieren, Weiterverbreiten und Anpassen für private und nicht-kommerzielle Zwecke.
- **Bedingungen:** Namensnennung (*Leon Wüste / Mindstorms123*), keine kommerzielle Nutzung, Weitergabe unter gleichen Bedingungen.

Details findest du in der [LICENSE](LICENSE)-Datei.

---

**Autor:** Leon Wüste ([@Mindstorms123](https://github.com/Mindstorms123))
