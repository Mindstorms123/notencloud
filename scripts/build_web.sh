#!/usr/bin/env bash
set -e

# Notencloud Web PWA Build & Packaging Script
# Optimiert für Standard-Shared-Webhosting (FTP/WebFTP) mit Hetzner Storage Share

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🎵 Notencloud Web PWA Build"
echo "=========================================="
echo "Arbeitsverzeichnis: $ROOT_DIR"

cd "$ROOT_DIR"

# 1. Icons aus assets/icon/app_icon.png generieren
echo ""
echo "🎨 [1/4] Web-Icons generieren..."
python3 - << 'EOF'
from PIL import Image
import os

src_path = "assets/icon/app_icon.png"
if os.path.exists(src_path):
    img = Image.open(src_path).convert("RGBA")
    web_dir = "web"
    icons_dir = os.path.join(web_dir, "icons")
    os.makedirs(icons_dir, exist_ok=True)

    img.resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, "Icon-192.png"), "PNG")
    img.resize((192, 192), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, "Icon-maskable-192.png"), "PNG")
    img.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, "Icon-512.png"), "PNG")
    img.resize((512, 512), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, "Icon-maskable-512.png"), "PNG")
    img.resize((180, 180), Image.Resampling.LANCZOS).save(os.path.join(icons_dir, "apple-touch-icon.png"), "PNG")
    img.resize((180, 180), Image.Resampling.LANCZOS).save(os.path.join(web_dir, "apple-touch-icon.png"), "PNG")
    img.resize((48, 48), Image.Resampling.LANCZOS).save(os.path.join(web_dir, "favicon.png"), "PNG")
    print("   ✓ Icons erfolgreich aktualisiert")
else:
    print("   ℹ assets/icon/app_icon.png nicht gefunden, überspringe Icon-Generierung")
EOF

# 2. Tests ausführen
echo ""
echo "🧪 [2/4] Tests und Code-Prüfung ausführen..."
flutter analyze
flutter test test/web_pwa_test.dart

# 3. Flutter Web Release kompilieren
echo ""
echo "🚀 [3/4] Flutter Web Release kompilieren..."
flutter build web --release

# Webhosting-Dateien (.htaccess, CORS-Proxy, Unzip-Helfer) sicherstellen
cp "$ROOT_DIR/web/.htaccess" "$ROOT_DIR/build/web/.htaccess" 2>/dev/null || true
cp "$ROOT_DIR/web/proxy.php" "$ROOT_DIR/build/web/proxy.php" 2>/dev/null || true
cp "$ROOT_DIR/web/unzip.php" "$ROOT_DIR/build/web/unzip.php" 2>/dev/null || true
cp "$ROOT_DIR/web/unzip.php" "$ROOT_DIR/build/unzip.php" 2>/dev/null || true

# 4. ZIP-Paket für einfachen Upload schnüren
echo ""
echo "📦 [4/4] Web-Paket schnüren (build/notencloud-web.zip)..."
mkdir -p "$ROOT_DIR/build"
cd "$ROOT_DIR/build/web"
zip -r -q "$ROOT_DIR/build/notencloud-web.zip" .
cd "$ROOT_DIR"

# Auch direkt ins Hauptverzeichnis kopieren für schnellen Zugriff
cp "$ROOT_DIR/build/notencloud-web.zip" "$ROOT_DIR/notencloud-web.zip"
cp "$ROOT_DIR/build/unzip.php" "$ROOT_DIR/unzip.php"

SIZE=$(du -h "$ROOT_DIR/build/notencloud-web.zip" | cut -f1)

echo ""
echo "=========================================="
echo "✅ Notencloud Web PWA erfolgreich erstellt!"
echo "Archiv: $ROOT_DIR/build/notencloud-web.zip ($SIZE)"
echo "WebFTP-Helfer: $ROOT_DIR/build/unzip.php"
echo ""
echo "Bereitstellung per WebFTP auf einfachem Shared-Hosting:"
echo "--------------------------------------------------------"
echo "Option A (WebFTP mit ZIP-Entpackfunktion):"
echo "  1. Lade 'build/notencloud-web.zip' in den Zielordner (z.B. /var/www/noten/)."
echo "  2. Klicke im WebFTP auf 'Entpacken'."
echo ""
echo "Option B (WebFTP OHNE Entpackfunktion):"
echo "  1. Lade 'build/notencloud-web.zip' UND 'build/unzip.php' in den Zielordner hoch."
echo "  2. Rufe im Browser einmal 'https://eure-domain.de/noten/unzip.php' auf."
echo "     -> Entpackt alles automatisch in 1 Sekunde und bereinigt sich selbst!"
echo "=========================================="
