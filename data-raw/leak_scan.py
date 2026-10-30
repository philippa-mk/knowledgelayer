#!/usr/bin/env python3
"""Leak scan for the knowledgelayer source tree, its shipped vocabulary and
its commit messages.

Two layers of rules:

* Public rules, written here: local paths, e-mail addresses other than the
  maintainer's published one and example addresses, account names, and (in
  the vocabulary only) hosting namespaces and any URI outside a crosswalk's
  `uri` field, because concepts are named by short ids, never by URIs. These
  run anywhere, including CI and the package's own tests.
* Private rules, never published: names specific to the vocabulary's source,
  given in a private file (--private) and read live from the source taxonomy
  (--core, --ref): every name and acronym in its jurisdiction-specific
  schemes. Nothing derived from them is written to disk. The private file
  also holds a short reviewed allow-list and the allowed phrases.

Without --private and --core the scan stops with exit 2 rather than pass
quietly. --public-only runs the public rules alone and says so.

Usage:
  python3 -I data-raw/leak_scan.py --private FILE --core DIR --ref REF [--history RANGE] [root]
  python3 -I data-raw/leak_scan.py --public-only [--history RANGE] [root]
"""
import argparse
import json
import os
import re
import subprocess
import sys

# Files that define or plant the public rules, and so contain their
# patterns: this scanner, its self-test, and the R helper and test that
# mirror it. None of them holds a source-specific term.
SELF = {"data-raw/leak_scan.py", "data-raw/test_leak_scan.py",
        "tests/testthat/helper-leak.R", "tests/testthat/test-leak.R"}
PUBLIC_RULES = [
    (r"/Users/[A-Za-z]", "a local macOS path"),
    (r"/home/[a-z]", "a local Linux path"),
    (r"(?i)[A-Z]:\\Users\\", "a local Windows path"),
    (r"~/Projects", "a local path"),
    (r"(?i)file://", "a local file link"),
    (r"\b[A-Za-z0-9._%+-]+@(?!example\.(?:org|com)\b|philippa\.page\b)[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b",
     "an e-mail address"),
    (r"(?i)users\.noreply\.github\.com", "an account's private address"),
    (r"git@github-[A-Za-z0-9-]+", "a local SSH host alias"),
]
# In the vocabulary only: no hosting namespace, so that no base URI is baked in.
PUBLIC_VOCAB_RULES = [
    (r"(?i)github\.io", "a hosting namespace"),
    (r"(?i)philippa\.page", "a candidate namespace"),
]
# Folders that hold private inputs and review records: never tracked, never
# in a built tarball.
PRIVATE_DIRS = ("private/", "review/")
URI = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*://|\bwww\.")
MAX_WORDS = 10


def compile_rules(pairs):
    out = []
    for pattern, why in pairs:
        flags = 0
        if pattern.startswith("(?i)"):
            pattern, flags = pattern[4:], re.IGNORECASE
        out.append((re.compile(pattern, flags), why))
    return out


def name_key(text):
    return " ".join(re.findall(r"[a-z0-9]+", text.lower()))


class Rules:
    """Everything the scan matches against, held in memory only."""

    def __init__(self, private=None, taxonomy=None):
        self.rules = compile_rules(PUBLIC_RULES)
        self.names, self.acronyms = set(), set()
        self.allow_names, self.allow_acronyms, self.phrases = set(), set(), []
        self.private = private is not None
        if private:
            self.rules += compile_rules(private["rules"])
            # A source id that ships under another id must never be named.
            self.rules += compile_rules([(re.escape(old) + r"(?![A-Za-z0-9-])", "a source id that ships renamed")
                                         for old in private.get("id_map", {})])
            for kind, term, _ in private.get("allow", []):
                (self.allow_names if kind == "name" else self.allow_acronyms).add(
                    name_key(term) if kind == "name" else term)
            self.phrases = private.get("allowed_phrases", [])
            # [scheme, minimum words]: in a scheme of program budgets, a one- or
            # two-word name is an ordinary phrase, so only longer names count.
            for scheme, min_words in private.get("name_schemes", []):
                cs = taxonomy["schemes"].get(scheme, {}).get("concepts", {})
                for c in (cs.values() if isinstance(cs, dict) else cs):
                    key = name_key(c.get("prefLabel") or "")
                    if len(key.split()) >= min_words:
                        self.names.add(key)
                    for ac in [c.get("acronym"), c.get("id", ":").split(":", 1)[1]]:
                        if ac and len(ac) >= 2 and re.fullmatch(r"[A-Z0-9]+", ac):
                            self.acronyms.add(ac)
            self.names.discard("")


def normalize(text):
    # Join wrapped lines, including roxygen's "#'" continuation, so an
    # allowed phrase matches however it is wrapped.
    return re.sub(r"\s*\n\s*(#'\s*)?", " ", text)


def scan_text(text, rules):
    """Return a list of (match, why) for one string."""
    text = normalize(text)
    for phrase in rules.phrases:
        text = text.replace(phrase, " ")
    hits = [(m.group(0), why) for rx, why in rules.rules for m in rx.finditer(text)]
    tokens = re.findall(r"[A-Za-z0-9]+", text)
    hits += [(t, "a jurisdiction-specific acronym") for t in tokens
             if t in rules.acronyms and t not in rules.allow_acronyms]
    low = [t.lower() for t in tokens]
    for n in range(1, MAX_WORDS + 1):
        for i in range(len(low) - n + 1):
            gram = " ".join(low[i:i + n])
            if gram in rules.names and gram not in rules.allow_names:
                hits.append((" ".join(tokens[i:i + n]), "a jurisdiction-specific name"))
    return hits


def scan_vocab(vocab, rules):
    """Scan every string in a vocabulary; URIs only inside mappings."""
    hits = []
    namespaces = compile_rules(PUBLIC_VOCAB_RULES)

    def walk(x, where, in_uri=False):
        if isinstance(x, dict):
            for k, v in x.items():
                walk(v, where + "." + k, in_uri=(k == "uri" and ".mappings" in where))
        elif isinstance(x, list):
            for i, v in enumerate(x):
                walk(v, "%s[%d]" % (where, i))
        elif isinstance(x, str):
            found = scan_text(x, rules)
            found += [(m.group(0), why) for rx, why in namespaces for m in rx.finditer(x)]
            if not in_uri:
                found += [(m.group(0), "a URI outside a crosswalk") for m in URI.finditer(x)]
            hits.extend((where, m, why) for m, why in found)

    walk(vocab, "$")
    return hits


def git(root, *args):
    return subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True,
                          check=True).stdout


def tracked_files(root):
    files = git(root, "ls-files", "-co", "--exclude-standard").splitlines()
    return [f for f in files if f and f not in SELF and os.path.isfile(os.path.join(root, f))]


def load_rules(args):
    if args.public_only:
        return Rules()
    if not (args.private and args.core and args.ref):
        sys.stderr.write("leak scan NOT RUN: the jurisdiction check needs --private, --core and --ref.\n"
                         "Use --public-only to run the public rules alone.\n")
        sys.exit(2)
    with open(args.private, encoding="utf-8") as f:
        private = json.load(f)
    taxonomy = json.loads(git(args.core, "show", args.ref + ":data/taxonomy/taxonomy.json"))
    return Rules(private, taxonomy)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default=os.getcwd())
    ap.add_argument("--private")
    ap.add_argument("--core")
    ap.add_argument("--ref")
    ap.add_argument("--public-only", action="store_true")
    ap.add_argument("--history", default="HEAD",
                    help="commits whose messages are scanned; the default, HEAD, is every commit back to the root")
    ap.add_argument("--tarball", help="also check that a built source tarball holds no private folder")
    args = ap.parse_args()
    rules = load_rules(args)
    problems = []
    files = tracked_files(args.root)
    for f in files:
        try:
            with open(os.path.join(args.root, f), encoding="utf-8") as fh:
                text = fh.read()
        except UnicodeDecodeError:
            continue
        if f == "inst/extdata/vocabulary.json":
            problems += [(f + " " + w, m, why) for w, m, why in scan_vocab(json.loads(text), rules)]
        else:
            problems += [(f, m, why) for m, why in scan_text(text, rules)]
    for f in git(args.root, "ls-files").splitlines():
        if f.startswith(PRIVATE_DIRS):
            problems.append((f, f.split("/")[0] + "/", "a private folder is tracked"))
    if args.tarball:
        import tarfile
        with tarfile.open(args.tarball) as t:
            for name in t.getnames():
                inner = name.split("/", 1)[1] if "/" in name else ""
                if inner.startswith(PRIVATE_DIRS) or inner.rstrip("/") in ("private", "review"):
                    problems.append((args.tarball, name, "a private folder is in the tarball"))
    log = [e for e in git(args.root, "log", "--format=%x00%h%n%B", args.history).split("\x00") if e]
    for entry in log:
        sha, _, body = entry.partition("\n")
        problems += [("commit " + sha, m, why) for m, why in scan_text(body, rules)]
    for where, m, why in problems:
        print("LEAK  %s: %r (%s)" % (where, m, why))
    scope = "public and private rules" if rules.private else "PUBLIC RULES ONLY (jurisdiction check not run)"
    print("leak scan, %s: %d files and %d commit messages (%s), %d problem(s)"
          % (scope, len(files), len(log), args.history, len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
