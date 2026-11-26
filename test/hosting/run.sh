#!/usr/bin/env bash
# Prüft install.php und proxy.php wie auf einem Webhosting: Einrichtung,
# Anmeldung, Einstellungen, Update und das Durchreichen großer Dateien.
# Braucht nur php (mit curl), curl und python3.   Aufruf: test/hosting/run.sh
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
site="$work/site"; release="$work/release"; pkg="$work/pkg"
mkdir -p "$site" "$release" "$pkg/assets/fonts"
NC_PORT=8795; SITE_PORT=8796; REL_PORT=8797
pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT

fail() { echo "FEHLER: $*" >&2; exit 1; }
has() { grep -q -- "$2" <<<"$1" || fail "erwartet: $2"; }

make_release() { # $1 = Fassung
  echo "<html>App $1</html>" > "$pkg/index.html"
  echo "font" > "$pkg/assets/fonts/a.ttf"
  : > "$pkg/leer.txt"
  echo "{\"version\":\"$1\"}" > "$pkg/version.json"
  echo '{"club":"darf nie ankommen"}' > "$pkg/config.json"
  cp "$root/web/proxy.php" "$root/web/install.php" "$root/web/.htaccess" "$pkg/"
  python3 - "$pkg" "$release/notencloud-web.zip" <<'PY'
import sys, zipfile, os
src, out = sys.argv[1:3]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for base, _, files in os.walk(src):
        for f in files:
            p = os.path.join(base, f)
            z.write(p, os.path.relpath(p, src))
    z.writestr("../ausbruch.txt", "darf nicht entpackt werden")
PY
  cp "$pkg/version.json" "$release/version.json"
}

serve() { ( cd "$1" && exec php -d memory_limit=24M -S "127.0.0.1:$2" ${3:-} >/dev/null 2>&1 ) & pids+=($!); }

make_release v1.0.0
cp "$root/web/install.php" "$site/"
serve "$work" $NC_PORT "$root/test/hosting/fake_nextcloud.php"
serve "$release" $REL_PORT
( cd "$site" && NOTENCLOUD_RELEASE_BASE="http://127.0.0.1:$REL_PORT/" exec php -d memory_limit=24M -S "127.0.0.1:$SITE_PORT" >/dev/null 2>&1 ) & pids+=($!)
for p in $NC_PORT $REL_PORT $SITE_PORT; do
  for _ in $(seq 50); do curl -s -o /dev/null "http://127.0.0.1:$p/" && break; sleep 0.1; done
done

url="http://127.0.0.1:$SITE_PORT/install.php"
jar="$work/cookies"
token() { curl -s -b "$jar" -c "$jar" "$url" | grep -o 'name="token" value="[^"]*"' | head -1 | cut -d'"' -f4; }
post() { curl -s -b "$jar" -c "$jar" "$url" --data-urlencode "token=$(token)" "$@"; }

echo "1. Einrichtungsseite"
page=$(curl -s -c "$jar" "$url")
has "$page" "Voraussetzungen"; has "$page" "Notencloud einrichten"

echo "2. Fehleingaben werden abgewiesen"
out=$(post -d action=install --data-urlencode "club=MV Test" --data-urlencode "server=http://127.0.0.1:$NC_PORT" -d folder=Noten -d password=kurz)
has "$out" "mindestens 10 Zeichen"
out=$(post -d action=install --data-urlencode "club=MV Test" --data-urlencode "server=http://127.0.0.1:$REL_PORT" -d folder=Noten -d password=langesPasswort1)
has "$out" "antwortet keine Nextcloud"
out=$(post -d action=install --data-urlencode "club=MV Test" --data-urlencode "server=http://127.0.0.1:$NC_PORT" -d folder=Noten -d password=langesPasswort1 --data-urlencode "konzertmeister=https://boese.example/x")
has "$out" "Konzertmeister-Link muss"
[ ! -e "$site/index.html" ] || fail "trotz Fehleingabe installiert"
out=$(curl -s -b "$jar" "$url" -d token=falsch -d action=install)
has "$out" "zu lange offen"

echo "3. Einrichtung"
out=$(post -d action=install --data-urlencode "club=MV Test & Söhne" \
  --data-urlencode "server=http://127.0.0.1:$NC_PORT/index.php/apps/files/" -d folder=Notenarchiv -d password=langesPasswort1 \
  --data-urlencode "konzertmeister=https://rest.konzertmeister.app/api/v3/org/X/upcomingappointments")
has "$out" "Die App läuft"; has "$out" "v1.0.0"
has "$out" "notencloud://setup?server=http%3A%2F%2F127.0.0.1%3A$NC_PORT&amp;folder=%2FNotenarchiv"
grep -q "App v1.0.0" "$site/index.html" || fail "index.html fehlt"
[ -f "$site/assets/fonts/a.ttf" ] && [ -f "$site/leer.txt" ] && [ -f "$site/proxy.php" ] || fail "Dateien fehlen"
[ ! -e "$work/ausbruch.txt" ] && [ ! -e "$site/ausbruch.txt" ] || fail "Pfad-Ausbruch entpackt"
ls "$site" | grep -q download && fail "Download nicht aufgeräumt"
python3 - "$site/config.json" "$NC_PORT" <<'PY' || fail "config.json falsch"
import json, sys
c = json.load(open(sys.argv[1], encoding="utf-8"))
assert c == {"club": "MV Test & Söhne", "server": f"http://127.0.0.1:{sys.argv[2]}", "folder": "/Notenarchiv",
             "konzertmeister": "https://rest.konzertmeister.app/api/v3/org/X/upcomingappointments"}, c
PY
php -r '$c = include $argv[1]; exit($c["hosts"] === ["127.0.0.1", "rest.konzertmeister.app"] && $c["origins"] === ["http://127.0.0.1:'$SITE_PORT'", "http://www.127.0.0.1:'$SITE_PORT'"] ? 0 : 1);' "$site/proxy.config.php" || fail "proxy.config.php falsch"
grep -q langesPasswort1 "$site/install.config.php" && fail "Passwort im Klartext gespeichert"

echo "4. Zweite Einrichtung ist gesperrt, Anmeldung nötig"
rm -f "$jar"
page=$(curl -s -c "$jar" "$url"); has "$page" "Passwort der Einrichtung"
out=$(post -d action=install --data-urlencode "club=Fremd" --data-urlencode "server=http://127.0.0.1:$NC_PORT" -d password=anderesPasswort1)
has "$out" "Passwort der Einrichtung"
grep -q "MV Test" "$site/config.json" || fail "Einstellungen überschrieben"
out=$(post -d action=update); has "$out" "Passwort der Einrichtung"
out=$(post -d action=login -d password=falschesPasswort); has "$out" "stimmt nicht"
out=$(post -d action=login -d password=langesPasswort1); has "$out" "Installiert: <strong>v1.0.0"; has "$out" "ihr seid aktuell"

echo "5. Update behält die Einstellungen"
make_release v1.1.0
out=$(curl -s -b "$jar" "$url"); has "$out" "Neueste: <strong>v1.1.0"
out=$(post -d action=update); has "$out" "auf dem Stand v1.1.0"
grep -q "App v1.1.0" "$site/index.html" || fail "Update nicht entpackt"
grep -q "MV Test" "$site/config.json" || fail "config.json beim Update überschrieben"

echo "6. Einstellungen ändern"
out=$(post -d action=settings --data-urlencode "club=Neuer Name" --data-urlencode "server=http://127.0.0.1:$NC_PORT" -d folder=/Noten -d konzertmeister=)
has "$out" "Einstellungen sind gespeichert"
grep -q '"club": "Neuer Name"' "$site/config.json" || fail "Name nicht gespeichert"
php -r '$c = include $argv[1]; exit($c["hosts"] === ["127.0.0.1"] ? 0 : 1);' "$site/proxy.config.php" || fail "Konzertmeister noch freigegeben"

echo "7. Archiv neben install.php (ohne Download)"
make_release v1.2.0; cp "$release/notencloud-web.zip" "$site/"; rm "$release/notencloud-web.zip"
out=$(post -d action=update); has "$out" "auf dem Stand v1.2.0"
[ ! -e "$site/notencloud-web.zip" ] || fail "Archiv nicht aufgeräumt"

echo "8. Proxy"
proxy="http://127.0.0.1:$SITE_PORT/proxy.php"
nc="http://127.0.0.1:$NC_PORT"
out=$(curl -s -o "$work/big" -w '%{http_code} %{size_download} %{content_type}' -D "$work/h" "$proxy?url=$nc/big.pdf")
[ "$out" = "200 41943040 application/pdf" ] || fail "großer Download: $out"
grep -qi '^etag: "gross"' "$work/h" && grep -qi '^content-length: 41943040' "$work/h" || fail "Header fehlen"
out=$(curl -s -X PROPFIND -H 'Depth: 1' -H 'Authorization: Basic abc' -H "Origin: http://127.0.0.1:$SITE_PORT" -d '<x/>' -w ' %{http_code}' "$proxy?url=$nc/remote.php/dav/files/u/")
has "$out" 'depth="1" auth="Basic abc"><x/></d:multistatus> 207'
out=$(curl -s -X PUT -d 'notiz' -D "$work/h" -w '%{http_code}' "$proxy?url=$nc/remote.php/dav/files/u/a.json")
[ "$out" = "201" ] && grep -qi '^etag:' "$work/h" || fail "PUT: $out"
[ "$(curl -s -X DELETE -o /dev/null -w '%{http_code}' "$proxy?url=$nc/x")" = "204" ] || fail "DELETE"
[ "$(curl -s -o /dev/null -w '%{http_code}' "$proxy?url=$nc/gibtsnicht")" = "404" ] || fail "404 nicht durchgereicht"
[ "$(curl -s -I -o /dev/null -m 5 -w '%{http_code}' "$proxy?url=$nc/status.php")" = "200" ] || fail "HEAD"
[ "$(curl -s -o /dev/null -w '%{http_code}' "$proxy?url=http://localhost:$NC_PORT/status.php")" = "403" ] || fail "fremder Server nicht abgewiesen"
[ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Origin: https://fremd.example' "$proxy?url=$nc/status.php")" = "403" ] || fail "fremde Seite nicht abgewiesen"
[ "$(curl -s -o /dev/null -w '%{http_code}' "$proxy?url=http://127.0.0.1:1/x")" = "502" ] || fail "502 bei unerreichbarem Server"

echo "Alle Hosting-Tests bestanden"
