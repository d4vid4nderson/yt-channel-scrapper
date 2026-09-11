#!/usr/bin/env python3
"""Check Patterns.swift against YouTube's current base.js.

The pattern table in Sources/Engine/Patterns.swift matches minified JavaScript that is
re-minified weekly. When the highest resolutions stop working, this is what says whether
the patterns still bite — and it runs anywhere, without Xcode or a device.

It reads the patterns out of Patterns.swift rather than restating them, so there is one
source of truth and a fix made here is a fix made in the app.

    ./check-patterns.py            # against the live base.js
    ./check-patterns.py --offline  # against built-in samples, no network

An offline run only proves the algorithm still handles the shapes it was written for; a
live run is the one that answers "is the app broken right now".
"""
import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

SWIFT = Path(__file__).resolve().parent.parent / "Sources" / "Engine" / "Patterns.swift"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36")


# --- reading the patterns out of the Swift ------------------------------------------

def swift_raw_strings(text, after, count=None):
    """The #"..."# literals following a marker in Patterns.swift."""
    tail = text[text.index(after):]
    found = re.findall(r'#"((?:[^"]|"(?!#))*)"#', tail)
    return found[:count] if count else found


def load_patterns():
    text = SWIFT.read_text()
    sig = swift_raw_strings(text, "signatureNamePatterns", 3)
    helper = swift_raw_strings(text, "helperCallPattern", 1)[0]
    n_call = swift_raw_strings(text, "transformCallPatterns", 3)
    player = swift_raw_strings(text, "static func playerHash", 1)[0]
    # globalPrelude assembles its two patterns from a shared `string` fragment, so it is
    # rebuilt the same way here instead of being read as a literal.
    frag = swift_raw_strings(text, "let string = ", 1)[0]
    prelude = [
        r"var\s+([a-zA-Z0-9_$]+)\s*=\s*" + frag + r"\s*\.\s*split\(\s*" + frag + r"\s*\)",
        r"var\s+([a-zA-Z0-9_$]+)\s*=\s*\[\s*(?:" + frag + r"\s*,\s*){8,}" + frag + r"\s*\]",
    ]
    return {"signature": sig, "helper": helper, "n_call": n_call,
            "prelude": prelude, "player": player}


# --- the algorithm, mirroring Patterns.swift ----------------------------------------

def skip_string(s, i):
    q = s[i]
    if q not in "\"'`":
        return None
    j = i + 1
    while j < len(s):
        if s[j] == "\\":
            j += 2
            continue
        if s[j] == q:
            return j + 1
        j += 1
    return None


def matching_brace(s, start):
    opener = s[start]
    closer = {"{": "}", "[": "]", "(": ")"}.get(opener)
    if not closer:
        return None
    depth, i = 0, start
    while i < len(s):
        if i > start:
            sk = skip_string(s, i)
            if sk is not None:
                i = sk
                continue
        if s[i] == opener:
            depth += 1
        elif s[i] == closer:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def function_named(name, s):
    if not name:
        return None
    esc = re.escape(name)
    for header in (r"(?:var\s+)?" + esc + r"\s*=\s*function\s*\([^)]*\)\s*\{",
                   r"function\s+" + esc + r"\s*\([^)]*\)\s*\{",
                   esc + r"\s*:\s*function\s*\([^)]*\)\s*\{"):
        m = re.search(header, s)
        if not m:
            continue
        end = matching_brace(s, m.end() - 1)
        if end is None:
            continue
        args = m.group(0)[m.group(0).find("(") + 1:m.group(0).find(")")]
        return "function(%s){%s}" % (args, s[m.end():end])
    return None


def object_literal(name, s):
    m = re.search(r"(?:var\s+)?" + re.escape(name) + r"\s*=\s*\{", s)
    if not m:
        return None
    end = matching_brace(s, m.end() - 1)
    return None if end is None else s[m.end() - 1:end + 1]


def array_elements(name, s):
    m = re.search(r"(?:var\s+)?" + re.escape(name) + r"\s*=\s*\[", s)
    if not m:
        return None
    start = m.end() - 1
    end = matching_brace(s, start)
    if end is None:
        return None
    out, cur, depth, i = [], "", 0, start + 1
    while i < end:
        sk = skip_string(s, i)
        if sk is not None:
            cur += s[i:sk]
            i = sk
            continue
        c = s[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "," and depth == 0:
            out.append(cur)
            cur, i = "", i + 1
            continue
        cur += c
        i += 1
    out.append(cur)
    return out


def first_group(patterns, text, group=1):
    for p in patterns:
        m = re.search(p, text)
        if m:
            return m.group(group), m
    return None, None


# --- the check ----------------------------------------------------------------------

def check(js, pat, label):
    print(f"\n=== {label} ({len(js):,} bytes) ===")
    ok = True

    name, _ = first_group(pat["signature"], js)
    body = function_named(name, js)
    print(f"  signature fn     {name or '—':<12} {'found' if body else 'NOT FOUND'}")
    ok &= body is not None

    if body:
        m = re.search(pat["helper"], body)
        helper = m.group(1) if m else None
        obj = object_literal(helper, js) if helper else None
        ops = obj.count("function") if obj else 0
        print(f"  helper object    {helper or '—':<12} "
              f"{'found, ' + str(ops) + ' ops' if obj else 'NOT FOUND'}")
        # A helper with no operations means the brace matcher stopped early.
        ok &= obj is not None and ops >= 2

    n_name, m = first_group(pat["n_call"], js)
    index = m.group(2) if m and m.lastindex and m.lastindex >= 2 else None
    n_body = None
    if n_name and index is not None:
        els = array_elements(n_name, js)
        if els and int(index) < len(els):
            el = els[int(index)].strip()
            n_body = el if el.startswith("function") else function_named(el, js)
    elif n_name:
        n_body = function_named(n_name, js)
    print(f"  n transform      {(n_name or '—') + (f'[{index}]' if index else ''):<12} "
          f"{'found' if n_body else 'NOT FOUND'}")
    ok &= n_body is not None

    pre, _ = first_group(pat["prelude"], js)
    # Absent is survivable — older players have no hoisted table — so this reports but
    # does not fail. A *wrong* one would, and that shows up as n transform returning nil.
    print(f"  hoisted table    {pre or '—':<12} {'found' if pre else 'absent (ok on older players)'}")

    print(f"  -> {'PASS' if ok else 'FAIL — update Patterns.swift'}")
    return ok


SAMPLES = {
    "sample: assignment form": (
        '"use strict";var uX=\'a|b|split|reverse|,|{"}\'.split("|");'
        'var Wt={ab:function(a,b){a.splice(0,b)},cd:function(a){a.reverse()},'
        'ef:function(a,b){var c=a[0];a[0]=a[b%a.length];a[b%a.length]=c}};'
        'var Pq=function(a){a=a.split("");Wt.cd(a);Wt.ab(a,3);Wt.ef(a,17);return a.join("")};'
        'var Nz=[function(a){var b=a.split("");return b.reverse().join("")}];'
        'var g=function(a,b){if(b=a.get("n"))&&(b=Nz[0](b),a.set("n",b));return a};'),
    "sample: declaration form": (
        '"use strict";var QQ="w,x,y,z".split(",");'
        'var Kd={GG:function(a,b){a.splice(0,b)},HH:function(a){a.reverse()}};'
        'function Rt(a){a=a.split("");Kd.HH(a);Kd.GG(a,2);return a.join("")}'
        'function nT(a){var b=a.split("");b.reverse();return b.join("")}'
        'var q=function(a){var b=a.get("n"))&&(b=nT(b);return b};'),
}


def fetch_live(pat):
    def get(url):
        request = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read().decode("utf-8", "replace")

    iframe = get("https://www.youtube.com/iframe_api")
    m = re.search(pat["player"], iframe)
    if not m:
        print("could not find the player hash in /iframe_api — "
              "check playerHash in Patterns.swift", file=sys.stderr)
        return None, None
    h = m.group(1)
    url = f"https://www.youtube.com/s/player/{h}/player_ias.vflset/en_US/base.js"
    return get(url), h


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--offline", action="store_true",
                    help="skip the live base.js and check the built-in samples only")
    ap.add_argument("--save", metavar="PATH",
                    help="write the fetched base.js here, to diff against a later one")
    args = ap.parse_args()

    pat = load_patterns()
    print(f"patterns read from {SWIFT.relative_to(SWIFT.parents[3])}")

    ok = all(check(js, pat, label) for label, js in SAMPLES.items())

    if not args.offline:
        try:
            js, h = fetch_live(pat)
        except Exception as exc:                                  # noqa: BLE001
            print(f"\ncould not reach YouTube ({exc}); samples only", file=sys.stderr)
            js = None
        if js:
            if args.save:
                Path(args.save).write_text(js)
                print(f"\nsaved base.js to {args.save}")
            ok &= check(js, pat, f"live base.js — player {h}")

    print()
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
