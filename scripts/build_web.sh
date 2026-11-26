#!/usr/bin/env bash
# Baut das Web-Paket für einfaches Webhosting (PHP, z. B. Hetzner Webhosting):
#   build/notencloud-web.zip   App + proxy.php + install.php + .htaccess
#   build/install.php          Einrichtungs-Skript (einzeln hochladbar)
#   build/version.json         Fassung des Pakets
# Dasselbe Paket läuft bei jedem Verein; die Vereinsdaten stehen in config.json,
# die install.php auf dem Webhosting anlegt (siehe docs/webhosting.md).
#
# Aufruf: scripts/build_web.sh [--ci] [Fassung]
#   --ci      ohne Icon-Erzeugung, Analyse und Tests (das Release-Workflow nutzt das)
#   Fassung   z. B. v1.3.0; Standard: Version aus pubspec.yaml
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ci=false
version=""
for arg in "$@"; do
  case "$arg" in
    --ci) ci=true ;;
    *) version="$arg" ;;
  esac
done
if [ -z "$version" ]; then
  version="v$(grep -m1 '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*([^+[:space:]]+).*/\1/')"
fi
commit="$(git rev-parse --short=8 HEAD 2>/dev/null || echo unbekannt)"

echo "Notencloud Web-Paket $version ($commit)"

if ! $ci; then
  echo "[1/4] Icons erzeugen"
  python3 - << 'PY' || echo "   (übersprungen: Python-Paket Pillow fehlt)"
from PIL import Image
import os

src_path = "assets/icon/app_icon.png"
img = Image.open(src_path).convert("RGBA")
icons_dir = os.path.join("web", "icons")
os.makedirs(icons_dir, exist_ok=True)
for name, size in [("Icon-192.png", 192), ("Icon-maskable-192.png", 192), ("Icon-512.png", 512),
                   ("Icon-maskable-512.png", 512), ("apple-touch-icon.png", 180)]:
    img.resize((size, size), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, name), "PNG")
img.resize((180, 180), Image.Resampling.LANCZOS).save(os.path.join("web", "apple-touch-icon.png"), "PNG")
img.resize((48, 48), Image.Resampling.LANCZOS).save(os.path.join("web", "favicon.png"), "PNG")
PY

  echo "[2/4] Analyse und Tests"
  flutter analyze
  flutter test test/web_pwa_test.dart test/app_config_test.dart
  test/hosting/run.sh
fi

echo "[3/4] Web-App bauen"
# Ohne NOTENCLOUD_PROXY_URL: Die App nutzt proxy.php neben sich.
# --no-web-resources-cdn: Grafik-Engine aus dem eigenen Build, sonst startet
# die App ohne Internet nicht.
flutter build web --release --no-web-resources-cdn "--dart-define=NOTENCLOUD_BUILD=$version"

out="build/web"
cp web/.htaccess web/proxy.php web/install.php "$out/"
# Offline-Dateiliste und Versionskennung (config.json steht mit auf der Liste)
scripts/web_postbuild.sh "$version" "$out"
# Die Vereins-Einstellungen gehören nicht ins Paket – ein Update darf sie nie überschreiben.
rm -f "$out/config.json" "$out/unzip.php"
printf '{"version":"%s","commit":"%s","built":"%s"}\n' "$version" "$commit" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$out/version.json"

echo "[4/4] Paket schnüren"
rm -f build/notencloud-web.zip
(cd "$out" && zip -r -q -X ../notencloud-web.zip . -x '*.symbols' '*.map')
cp "$out/install.php" "$out/version.json" build/

echo
echo "Fertig: build/notencloud-web.zip ($(du -h build/notencloud-web.zip | cut -f1)), build/install.php, build/version.json"
echo "Einrichtung auf dem Webhosting: docs/webhosting.md"
