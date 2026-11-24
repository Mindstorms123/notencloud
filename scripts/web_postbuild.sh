#!/usr/bin/env bash
# Bereitet build/web für die Auslieferung als statische Seite vor:
#   - App-Dateien bekommen eine Versionskennung (Updates kommen sofort an)
#   - sw.js erhält Version und Dateiliste für den Offline-Betrieb
# Aufruf: scripts/web_postbuild.sh <version> [verzeichnis]
set -euo pipefail
v="${1:?Version fehlt}"
dir="${2:-build/web}"

sed -i "s|\"mainJsPath\":\"main.dart.js\"|\"mainJsPath\":\"main.dart.js?v=$v\"|" "$dir/flutter_bootstrap.js"
sed -i "s|flutter_bootstrap.js\"|flutter_bootstrap.js?v=$v\"|" "$dir/index.html"
grep -q "main.dart.js?v=$v" "$dir/flutter_bootstrap.js"
grep -q "flutter_bootstrap.js?v=$v" "$dir/index.html"

# Dateiliste für den Offline-Speicher. Nicht benötigte Render-Varianten
# (skwasm, wimp) und Hilfsdateien bleiben draußen.
list=$(cd "$dir" && find . -type f \
  ! -name 'sw.js' ! -name '*.symbols' ! -name '*.map' ! -name '*.php' ! -name '.htaccess' \
  ! -name 'skwasm*' ! -name 'wimp*' ! -name 'flutter_service_worker.js' ! -name 'NOTICES' \
  ! -name 'index.html' ! -name 'main.dart.js' ! -name 'flutter_bootstrap.js' \
  | sed 's|^\./||' | sort | python3 -c '
import sys, json, urllib.parse
v = sys.argv[1]
files = [urllib.parse.quote(l.strip()) for l in sys.stdin if l.strip()]
files = ["./", "flutter_bootstrap.js?v=" + v, "main.dart.js?v=" + v] + files
print(", ".join(json.dumps(f) for f in files))' "$v")

python3 - "$dir/sw.js" "$v" "$list" <<'PY'
import sys
path, version, files = sys.argv[1:4]
s = open(path, encoding="utf-8").read()
assert "__VERSION__" in s and "/*__PRECACHE__*/" in s
s = s.replace("__VERSION__", version).replace("/*__PRECACHE__*/", files)
open(path, "w", encoding="utf-8").write(s)
PY
echo "Web-Build vorbereitet: Version $v, $(echo "$list" | tr ',' '\n' | wc -l) Dateien im Offline-Speicher"
