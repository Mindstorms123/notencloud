#!/usr/bin/env bash
set -e

# ==============================================================================
# Notencloud - Direkt-Installer & Updater für Google Pixel via ADB
# ==============================================================================

# Farben für Terminalausgabe
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo -e "${BOLD}${CYAN}=====================================================${NC}"
echo -e "${BOLD}${CYAN}   Notencloud - Pixel ADB Fast Installer / Updater   ${NC}"
echo -e "${BOLD}${CYAN}=====================================================${NC}\n"

# Umgebungsvariablen für Flutter, JDK 17 und Android SDK setzen
export JAVA_HOME="/home/leon/development/jdk17"
export ANDROID_HOME="/home/leon/.bubblewrap/android_sdk"
export PATH="$JAVA_HOME/bin:/home/leon/development/flutter/bin:$ANDROID_HOME/platform-tools:$PATH"

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
PROJECT_DIR="$( cd -P "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd )"
if [ ! -f "$PROJECT_DIR/pubspec.yaml" ] && [ -f "$SCRIPT_DIR/pubspec.yaml" ]; then
    PROJECT_DIR="$SCRIPT_DIR"
fi
cd "$PROJECT_DIR"

BUILD_TYPE="release"
LAUNCH_AFTER="true"

# Parameter parsen
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --debug|-d) BUILD_TYPE="debug" ;;
        --release|-r) BUILD_TYPE="release" ;;
        --no-launch) LAUNCH_AFTER="false" ;;
        --help|-h)
            echo "Verwendung: $0 [--release | --debug] [--no-launch]"
            echo "  --release (Standard): Baut und installiert optimierte Release-APK"
            echo "  --debug:              Baut und installiert Debug-APK (schneller)"
            echo "  --no-launch:          App nach Installation nicht automatisch starten"
            exit 0
            ;;
        *) echo "Unbekannter Parameter: $1"; exit 1 ;;
    esac
    shift
done

# 1. Prüfen ob adb verfügbar ist
if ! command -v adb &> /dev/null; then
    echo -e "${RED}[Fehler] adb wurde nicht gefunden!${NC}"
    exit 1
fi

echo -e "${BLUE}▶ 1. Prüfe verbundene Geräte via ADB...${NC}"

# Bekannte WLAN-IP prüfen / versuchen zu verbinden falls kein Gerät da ist
CURRENT_DEVICES=$(adb devices | grep -v "List" | grep "device$" | awk '{print $1}')

if [ -z "$CURRENT_DEVICES" ]; then
    echo -e "${YELLOW}Kein Gerät direkt gefunden. Versuche WLAN-ADB Verbindung (192.168.178.254:45475)...${NC}"
    adb connect 192.168.178.254:45475 || true
    sleep 1
    CURRENT_DEVICES=$(adb devices | grep -v "List" | grep "device$" | awk '{print $1}')
fi

if [ -z "$CURRENT_DEVICES" ]; then
    echo -e "${RED}[Fehler] Kein Android-Gerät über ADB verbunden!${NC}"
    echo -e "Bitte stelle sicher, dass Entwickleroptionen & USB-/WLAN-Debugging auf deinem Pixel aktiviert sind."
    exit 1
fi

TARGET_DEVICE=$(echo "$CURRENT_DEVICES" | head -n 1)
DEVICE_MODEL=$(adb -s "$TARGET_DEVICE" shell getprop ro.product.model 2>/dev/null | tr -d '\r' || echo "Android Gerät")

echo -e "${GREEN}✓ Zielgerät gefunden:${NC} ${BOLD}$DEVICE_MODEL${NC} ($TARGET_DEVICE)\n"

# 2. APK bauen
echo -e "${BLUE}▶ 2. Baue Notencloud APK (${BUILD_TYPE})...${NC}"
if [ "$BUILD_TYPE" = "release" ]; then
    flutter build apk --release
    APK_PATH="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"
else
    flutter build apk --debug
    APK_PATH="$PROJECT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
fi

if [ ! -f "$APK_PATH" ]; then
    echo -e "${RED}[Fehler] APK konnte nicht gebaut werden: $APK_PATH${NC}"
    exit 1
fi

APK_SIZE=$(du -h "$APK_PATH" | cut -f1)
echo -e "${GREEN}✓ APK erfolgreich erstellt (${APK_SIZE})${NC}\n"

# 3. APK auf das Pixel übertragen & installieren
echo -e "${BLUE}▶ 3. Installiere Notencloud auf ${DEVICE_MODEL}...${NC}"
adb -s "$TARGET_DEVICE" install -r "$APK_PATH"
echo -e "${GREEN}✓ Installation erfolgreich abgeschlossen!${NC}\n"

# 4. App starten (optional)
if [ "$LAUNCH_AFTER" = "true" ]; then
    echo -e "${BLUE}▶ 4. Starte Notencloud auf ${DEVICE_MODEL}...${NC}"
    adb -s "$TARGET_DEVICE" shell am start -n de.blasorchester1862.notencloud/.MainActivity > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ App gestartet!${NC}\n"
fi

echo -e "${BOLD}${GREEN}=====================================================${NC}"
echo -e "${BOLD}${GREEN}   Notencloud ist auf deinem Pixel auf dem neuesten Stand!   ${NC}"
echo -e "${BOLD}${GREEN}=====================================================${NC}"
