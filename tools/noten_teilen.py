#!/usr/bin/env python3
"""Teilt einen Stapel-Scan in einzelne Stimmen und legt sie so ab, wie Notencloud sie erwartet.

    <Ziel>/<Kategorie>/<Stück>/<Instrument> <Stimme> in <Stimmung>.pdf

Welche Seiten zu welcher Stimme gehören, steht in einem Plan (JSON). Den Plan schreibt
ein Mensch oder eine KI, die sich die Seiten angesehen hat – dieses Skript prüft ihn
und schneidet. Es löscht und überschreibt nichts.

    python3 noten_teilen.py pruefen plan.json
    python3 noten_teilen.py teilen  plan.json --ziel ~/Nextcloud/Noten

Plan:
    {
      "quelle": "scan_2026-11-27.pdf",
      "kategorie": "01_Aktuelle Noten",
      "leerseiten": [4, 9],
      "stuecke": [
        {
          "titel": "Alte Kameraden",
          "stimmen": [
            {"datei": "Partitur.pdf",            "seiten": "1-3"},
            {"datei": "Flöte 1.pdf",             "seiten": "5-6"},
            {"datei": "Klarinette 2 in B.pdf",   "seiten": "7-8", "drehen": 180}
          ]
        }
      ]
    }

Seiten zählen ab 1. "seiten" darf Bereiche und Einzelseiten mischen: "1-3, 7".
Braucht:  pip install pypdf
"""
import argparse
import json
import re
import sys
from pathlib import Path

# Wörter, an denen Notencloud ein Instrument erkennt (Auszug aus lib/services/voice_matcher.dart).
BEKANNT = """
flöte floete flute piccolo oboe fagott bassoon klarinette clarinet bassklarinette
sopransax altsax tenorsax baritonsax saxophon saxophone sax
trompete trumpet kornett cornet flügelhorn fluegelhorn flugelhorn horn waldhorn
posaune trombone tenorhorn bariton baritone euphonium tuba bässe baesse sousaphon
percussion perkussion schlagzeug drums drumset snare trommel pauken pauke timpani
mallets glockenspiel xylophon xylophone marimba vibraphon bells becken cymbals triangel
klavier piano keyboard gitarre guitar bass gesang vocal chor harfe harp
violine geige viola bratsche violoncello cello kontrabass
partitur score direktion conductor
""".split()

VERBOTEN = re.compile(r'[\\/:*?"<>|\x00-\x1f]')


def seiten_liste(text, quelle_seiten):
    """'1-3, 7' -> [1, 2, 3, 7]"""
    seiten = []
    for teil in str(text).replace(";", ",").split(","):
        teil = teil.strip()
        if not teil:
            continue
        treffer = re.fullmatch(r"(\d+)\s*[-–]\s*(\d+)", teil)
        if treffer:
            a, b = int(treffer.group(1)), int(treffer.group(2))
            if a > b:
                raise ValueError(f"Bereich rückwärts: {teil}")
            seiten.extend(range(a, b + 1))
        elif teil.isdigit():
            seiten.append(int(teil))
        else:
            raise ValueError(f"Seitenangabe nicht lesbar: {teil!r}")
    for s in seiten:
        if not 1 <= s <= quelle_seiten:
            raise ValueError(f"Seite {s} gibt es nicht (der Scan hat {quelle_seiten} Seiten)")
    if not seiten:
        raise ValueError("keine Seiten angegeben")
    return seiten


def name_pruefen(name, art):
    if not name or name != name.strip() or VERBOTEN.search(name) or name in (".", "..") or name.endswith("."):
        raise ValueError(f"{art} {name!r} enthält Zeichen, die in Dateinamen nicht gehen")


def plan_laden(pfad):
    plan = json.loads(Path(pfad).read_text(encoding="utf-8"))
    quelle = Path(plan["quelle"]).expanduser()
    if not quelle.is_absolute():
        quelle = Path(pfad).resolve().parent / quelle
    if not quelle.is_file():
        raise ValueError(f"Scan nicht gefunden: {quelle}")
    return plan, quelle


def pruefen(plan, quelle_seiten):
    """Gibt (Aufträge, Warnungen) zurück; wirft ValueError bei Fehlern."""
    fehler, warnungen, auftraege = [], [], []
    belegt = {}
    kategorie = plan.get("kategorie", "").strip()
    try:
        name_pruefen(kategorie, "Kategorie")
    except ValueError as e:
        fehler.append(str(e))

    def belegen(seite, wofuer):
        if seite in belegt:
            fehler.append(f"Seite {seite} ist doppelt vergeben: {belegt[seite]} und {wofuer}")
        belegt[seite] = wofuer

    for s in plan.get("leerseiten", []):
        if not isinstance(s, int) or not 1 <= s <= quelle_seiten:
            fehler.append(f"Leerseite {s!r} gibt es nicht")
        else:
            belegen(s, "Leerseite")

    ziele = set()
    for stueck in plan.get("stuecke", []):
        titel = str(stueck.get("titel", "")).strip()
        try:
            name_pruefen(titel, "Stücktitel")
        except ValueError as e:
            fehler.append(str(e))
            continue
        if titel.startswith(("_", ".")):
            fehler.append(f"Stücktitel {titel!r} darf nicht mit _ oder . beginnen")
        if not stueck.get("stimmen"):
            fehler.append(f"{titel}: keine Stimmen")
        for stimme in stueck.get("stimmen", []):
            datei = str(stimme.get("datei", ""))
            wofuer = f"{titel}/{datei}"
            try:
                name_pruefen(datei, "Dateiname")
                if not datei.lower().endswith(".pdf"):
                    raise ValueError(f"{wofuer}: Dateiname muss auf .pdf enden")
                seiten = seiten_liste(stimme.get("seiten", ""), quelle_seiten)
                drehen = stimme.get("drehen", 0)
                if drehen not in (0, 90, 180, 270):
                    raise ValueError(f"{wofuer}: drehen muss 0, 90, 180 oder 270 sein")
            except ValueError as e:
                fehler.append(f"{wofuer}: {e}" if wofuer not in str(e) else str(e))
                continue
            schluessel = (titel.lower(), datei.lower())
            if schluessel in ziele:
                fehler.append(f"{wofuer} kommt doppelt vor")
            ziele.add(schluessel)
            for s in seiten:
                belegen(s, wofuer)
            if seiten != sorted(seiten):
                warnungen.append(f"{wofuer}: Seiten nicht aufsteigend ({stimme['seiten']}) – Absicht?")
            klein = datei.lower()
            if not any(wort in klein for wort in BEKANNT):
                warnungen.append(f"{wofuer}: kein bekanntes Instrument im Namen – erscheint in der App als Zusatzstimme")
            auftraege.append((kategorie, titel, datei, seiten, drehen))

    fehlend = [s for s in range(1, quelle_seiten + 1) if s not in belegt]
    if fehlend:
        fehler.append("Seiten ohne Zuordnung (Stimme oder \"leerseiten\"): " + ", ".join(map(str, fehlend)))
    if fehler:
        raise ValueError("\n".join(fehler))
    return auftraege, warnungen


def main():
    parser = argparse.ArgumentParser(description="Stapel-Scan in Stimmen teilen (Notencloud)")
    parser.add_argument("befehl", choices=["pruefen", "teilen"])
    parser.add_argument("plan")
    parser.add_argument("--ziel", help="Notenordner, z. B. der synchronisierte Nextcloud-Ordner 'Noten'")
    args = parser.parse_args()

    try:
        from pypdf import PdfReader, PdfWriter
    except ImportError:
        sys.exit("Das Python-Paket pypdf fehlt:  pip install pypdf")

    try:
        plan, quelle = plan_laden(args.plan)
        reader = PdfReader(str(quelle))
        anzahl = len(reader.pages)
        auftraege, warnungen = pruefen(plan, anzahl)
    except (ValueError, KeyError, json.JSONDecodeError) as e:
        sys.exit(f"Plan nicht in Ordnung:\n{e}")

    for w in warnungen:
        print("Hinweis:", w)
    stuecke = sorted({a[1] for a in auftraege})
    print(f"Plan in Ordnung: {anzahl} Seiten → {len(auftraege)} Stimmen in {len(stuecke)} Stück(en), "
          f"{len(plan.get('leerseiten', []))} Leerseiten")
    if args.befehl == "pruefen":
        for kategorie, titel, datei, seiten, _ in auftraege:
            print(f"  {kategorie}/{titel}/{datei}  ← Seiten {seiten[0]}–{seiten[-1]} ({len(seiten)})")
        return

    if not args.ziel:
        sys.exit("Bitte mit --ziel den Notenordner angeben.")
    ziel = Path(args.ziel).expanduser()
    if not ziel.is_dir():
        sys.exit(f"Zielordner nicht gefunden: {ziel}")
    vorhanden = [ziel / k / t / d for k, t, d, _, _ in auftraege if (ziel / k / t / d).exists()]
    if vorhanden:
        sys.exit("Diese Dateien gibt es schon – nichts wurde geschrieben:\n" + "\n".join(f"  {p}" for p in vorhanden))

    for kategorie, titel, datei, seiten, drehen in auftraege:
        writer = PdfWriter()
        for s in seiten:
            seite = writer.add_page(reader.pages[s - 1])
            if drehen:
                seite.rotate(drehen)
        pfad = ziel / kategorie / titel / datei
        pfad.parent.mkdir(parents=True, exist_ok=True)
        with open(pfad, "xb") as f:
            writer.write(f)
        print(f"  geschrieben: {pfad.relative_to(ziel)} ({len(seiten)} Seiten)")
    print("Fertig. Der Scan selbst wurde nicht verändert.")


if __name__ == "__main__":
    main()
