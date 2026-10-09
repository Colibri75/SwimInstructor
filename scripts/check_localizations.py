#!/usr/bin/env python3
"""Prüft, ob jeder Text der App in jeder Sprache übersetzt ist.

Aufruf (macht die test-Lane nach dem xcodebuild-Lauf mit SWIFT_EMIT_LOC_STRINGS=YES):
    python3 scripts/check_localizations.py <Ordner mit .stringsdata> [...]

Der Compiler legt für jede Swift-Datei eine .stringsdata-Datei mit allen Texten ab, die übersetzt werden
(Text("…"), Button("…"), String(localized: "…") usw.). Jeder dieser Schlüssel muss in jeder
Localization/<Sprache>.lproj/Localizable.strings stehen, und die Platzhalter (%@, %lld, …) der Übersetzung müssen
zu denen des Schlüssels passen, sonst stürzt die App beim Formatieren ab. Schlüssel ohne Buchstaben (z. B. "%lld")
brauchen keine Übersetzung.

Mit --dump schreibt das Skript zusätzlich alle Schlüssel des Codes als JSON nach stdout (für neue Sprachen).
"""
import base64
import gzip
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALIZATION = os.path.join(ROOT, "Localization")
SPECIFIER = re.compile(r"%(?:(\d+)\$)?[-+ #0']*\d*(?:\.\d+)?(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfFeEgGcCsSpaA%])")


def parse_strings(path):
    """Liest eine .strings-Datei im Format "Schlüssel" = "Wert"; (mit Kommentaren)."""
    text = open(path, encoding="utf-8").read()
    entries = {}
    i, n = 0, len(text)

    def read_quoted(pos):
        assert text[pos] == '"', f"{path}: Anführungszeichen erwartet bei {pos}"
        pos += 1
        out = []
        while True:
            ch = text[pos]
            if ch == "\\":
                nxt = text[pos + 1]
                out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\", "r": "\r"}.get(nxt, "\\" + nxt))
                pos += 2
            elif ch == '"':
                return "".join(out), pos + 1
            else:
                out.append(ch)
                pos += 1

    while i < n:
        if text[i].isspace() or text[i] == ";":
            i += 1
        elif text.startswith("//", i):
            i = text.index("\n", i) if "\n" in text[i:] else n
        elif text.startswith("/*", i):
            i = text.index("*/", i) + 2
        elif text[i] == '"':
            key, i = read_quoted(i)
            while text[i].isspace():
                i += 1
            assert text[i] == "=", f"{path}: '=' erwartet nach {key!r}"
            i += 1
            while text[i].isspace():
                i += 1
            value, i = read_quoted(i)
            if key in entries:
                raise SystemExit(f"{path}: Schlüssel doppelt: {key!r}")
            entries[key] = value
        else:
            raise SystemExit(f"{path}: unerwartetes Zeichen {text[i]!r} bei {i}")
    return entries


def specifiers(s):
    """Platzhalter nach Position, z. B. {1: 'object', 2: 'int'}."""
    result, index = {}, 0
    for match in SPECIFIER.finditer(s):
        position, length, conversion = match.groups()
        if conversion == "%":
            continue
        index += 1
        pos = int(position) if position else index
        if conversion == "@":
            kind = "object"
        elif conversion in "fFeEgGaA":
            kind = "double"
        elif conversion in "cC":
            kind = "char"
        elif conversion in "sS":
            kind = "cstring"
        elif conversion == "p":
            kind = "pointer"
        else:
            kind = "int64" if length in ("ll", "q", "j") else "int"
        result[pos] = kind
    return result


def code_keys(folders):
    keys = {}
    for folder in folders:
        for dirpath, _, files in os.walk(folder):
            for name in files:
                if not name.endswith(".stringsdata"):
                    continue
                data = json.load(open(os.path.join(dirpath, name), encoding="utf-8"))
                source = os.path.basename(data.get("source", name))
                for table, items in (data.get("tables") or {}).items():
                    if table != "Localizable":
                        continue
                    for item in items:
                        keys.setdefault(item["key"], set()).add(source)
    return keys


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dump = "--dump" in sys.argv
    keys = code_keys(args)
    if not keys:
        raise SystemExit("Keine .stringsdata gefunden - lief xcodebuild mit SWIFT_EMIT_LOC_STRINGS=YES?")
    needed = {k: v for k, v in keys.items() if re.search(r"[^\W\d_]", SPECIFIER.sub("", k))}
    print(f"Übersetzungen: {len(needed)} Texte im Code ({len(keys)} Schlüssel insgesamt)")

    if dump:
        # Kompakt (gzip + base64), damit die Liste in ein CI-Log passt.
        packed = base64.b64encode(gzip.compress(json.dumps({k: sorted(v) for k, v in sorted(needed.items())}, ensure_ascii=False).encode())).decode()
        for start in range(0, len(packed), 2000):
            print("KEYS-GZ " + packed[start:start + 2000])

    languages = sorted(d[:-6] for d in os.listdir(LOCALIZATION) if d.endswith(".lproj"))
    errors = []
    for language in languages:
        path = os.path.join(LOCALIZATION, f"{language}.lproj", "Localizable.strings")
        table = parse_strings(path) if os.path.exists(path) else {}
        missing = sorted(k for k in needed if k not in table)
        shown = missing if language == "en" else missing[:3]
        for key in shown:
            errors.append(f"{language}: fehlt {key!r} ({', '.join(sorted(needed[key]))})")
        if len(missing) > len(shown):
            errors.append(f"{language}: und {len(missing) - len(shown)} weitere fehlende Texte")
        for key, value in table.items():
            if specifiers(key) != specifiers(value):
                errors.append(f"{language}: Platzhalter passen nicht: {key!r} -> {value!r}")
        unused = sorted(k for k in table if k not in keys)
        if unused and language == "en":
            for key in unused:
                print(f"Hinweis en: ohne Text im Code: {key!r}")
        elif unused:
            print(f"Hinweis {language}: {len(unused)} Übersetzungen ohne Text im Code")
        print(f"{language}: {len(needed) - len(missing)}/{len(needed)} übersetzt")

    if errors:
        print("\n".join(errors))
        sys.stdout.flush()
        raise SystemExit(f"{len(errors)} Übersetzungsfehler, siehe oben (Anleitung: docs/uebersetzungen.md)")
    print("Alle Texte in allen Sprachen übersetzt.")


if __name__ == "__main__":
    main()
