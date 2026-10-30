#!/usr/bin/env python3
"""Self-test for data-raw/leak_scan.py, with an invented jurisdiction.

Runs anywhere (CI included): it builds a throwaway git repository and a
throwaway source taxonomy for "Zenithville", whose police department is the
"ZPD", and checks that the scanner catches them, honors its allow-list and
budget-name threshold, scans commit messages, and refuses to run without
its private inputs. Usage: python3 -I data-raw/test_leak_scan.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCAN = os.path.join(HERE, "leak_scan.py")
failures = []


def check(name, ok):
    print(("ok    " if ok else "FAIL  ") + name)
    if not ok:
        failures.append(name)


def git(d, *args):
    subprocess.run(["git", "-C", d] + list(args), check=True, capture_output=True,
                   env=dict(os.environ, GIT_AUTHOR_NAME="test", GIT_AUTHOR_EMAIL="noreply@local",
                            GIT_COMMITTER_NAME="test", GIT_COMMITTER_EMAIL="noreply@local"))


def scan(repo, *args):
    r = subprocess.run([sys.executable, "-I", SCAN] + list(args) + [repo], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


with tempfile.TemporaryDirectory() as tmp:
    core, repo = os.path.join(tmp, "core"), os.path.join(tmp, "repo")
    os.makedirs(os.path.join(core, "data", "taxonomy"))
    os.makedirs(repo)
    taxonomy = {"schemes": {
        "agencies": {"concepts": {"agency:ZPD": {"id": "agency:ZPD", "prefLabel": "Zenithville Police Department",
                                                 "acronym": "ZPD"}}},
        "budget_units": {"concepts": [{"id": "program:x", "prefLabel": "Compliance"},
                                      {"id": "program:y", "prefLabel": "Zenith Harbor Dredging Program"}]},
        "funds": {"concepts": [{"id": "fund:hwy", "prefLabel": "Interstate Road Fund"}]}}}
    with open(os.path.join(core, "data", "taxonomy", "taxonomy.json"), "w") as f:
        json.dump(taxonomy, f)
    git(core, "init", "-q")
    git(core, "add", ".")
    git(core, "commit", "-q", "-m", "taxonomy")
    private = os.path.join(tmp, "private.json")
    with open(private, "w") as f:
        json.dump({"rules": [["\\bZenithville\\b", "the invented city"]],
                   "allow": [["name", "Interstate Road Fund", "a national fund"]],
                   "allowed_phrases": ["credit to the Zenithville project"],
                   "name_schemes": [["agencies", 1], ["funds", 1], ["budget_units", 3]]}, f)
    git(repo, "init", "-q")

    def write(name, text, message="add"):
        with open(os.path.join(repo, name), "w") as f:
            f.write(text)
        git(repo, "add", name)
        git(repo, "commit", "-q", "-m", message)

    write("clean.md", "A review of procurement and compliance.\n")
    priv = ["--private", private, "--core", core, "--ref", "HEAD"]
    code, out = scan(repo, *priv)
    check("a clean tree passes", code == 0)
    code, out = scan(repo)
    check("without private inputs the scan refuses to run (exit 2)", code == 2 and "NOT RUN" in out)
    code, out = scan(repo, "--public-only")
    check("--public-only says the jurisdiction check did not run",
          code == 0 and "PUBLIC RULES ONLY" in out)
    write("leak.md", "Records from the ZPD.\n")
    code, out = scan(repo, *priv)
    check("an agency acronym from the source is caught", code == 1 and "'ZPD'" in out)
    write("leak.md", "Records from the zenithville police department.\n")
    code, out = scan(repo, *priv)
    check("an agency name is caught in any case", code == 1 and "police department" in out.lower())
    write("leak.md", "Paid from the Interstate Road Fund, for compliance.\n")
    code, out = scan(repo, *priv)
    check("allow-listed and short budget names pass", code == 0)
    write("leak.md", "The Zenith Harbor Dredging Program.\n")
    code, out = scan(repo, *priv)
    check("a long budget-unit name is caught", code == 1)
    write("leak.md", "This was a credit to the Zenithville\nproject.\n")
    code, out = scan(repo, *priv)
    check("an allowed phrase passes, even wrapped", code == 0)
    write("leak.md", "Saved at /Users/someone/x.\n")
    code, out = scan(repo, "--public-only")
    check("a local path is caught by the public rules", code == 1)
    write("leak.md", "Write to someone@agency.gov.\n")
    code, out = scan(repo, "--public-only")
    check("an e-mail address is caught", code == 1)
    write("leak.md", "Write to analyst.a@example.org or hello@philippa.page.\n")
    code, out = scan(repo, "--public-only")
    check("example and maintainer addresses pass", code == 0)
    os.makedirs(os.path.join(repo, "inst", "extdata"))
    write("inst/extdata/vocabulary.json", json.dumps({"concepts": [
        {"id": "ft:x", "prefLabel": "X", "mappings": [{"uri": "https://someone.github.io/x"}]}]}))
    code, out = scan(repo, "--public-only")
    check("a hosting namespace in the vocabulary is caught", code == 1 and "namespace" in out)
    write("inst/extdata/vocabulary.json", json.dumps({"concepts": [
        {"id": "ft:x", "prefLabel": "X", "mappings": [{"uri": "https://www.gao.gov/greenbook"}]}]}))
    os.makedirs(os.path.join(repo, "private"))
    write("private/notes.json", "{}")
    code, out = scan(repo, "--public-only")
    check("a tracked file under private/ is caught", code == 1 and "private folder is tracked" in out)
    git(repo, "rm", "-q", "--cached", "private/notes.json")
    git(repo, "commit", "-q", "-m", "untrack")
    import tarfile
    tgz = os.path.join(tmp, "pkg.tar.gz")
    with tarfile.open(tgz, "w:gz") as t:
        t.add(os.path.join(repo, "leak.md"), arcname="pkg/review/page.html")
    code, out = scan(repo, "--public-only", "--tarball", tgz)
    check("a review/ folder in a tarball is caught", code == 1 and "in the tarball" in out)
    with tarfile.open(tgz, "w:gz") as t:
        t.add(os.path.join(repo, "leak.md"), arcname="pkg/R/code.R")
    code, out = scan(repo, "--public-only", "--tarball", tgz)
    check("a clean tarball passes", code == 0)
    with open(private) as f:
        cfg = json.load(f)
    cfg["id_map"] = {"zone:old-name": "zone:new-name"}
    with open(private, "w") as f:
        json.dump(cfg, f)
    write("leak.md", "See zone:old-name for details.\n")
    code, out = scan(repo, *priv)
    check("a source id that ships renamed is caught", code == 1 and "renamed" in out)
    write("leak.md", "See zone:old-names and zone:new-name.\n")
    code, out = scan(repo, *priv)
    check("only the exact source id is caught", code == 0)
    write("leak.md", "clean again\n", message="Moved the Zenithville extract")
    code, out = scan(repo, *priv)
    check("a commit message is scanned", code == 1 and "commit" in out)

with tempfile.TemporaryDirectory() as tmp:
    # The root commit is scanned too: a leak in the very first message.
    root = os.path.join(tmp, "rootrepo")
    os.makedirs(root)
    git(root, "init", "-q")
    with open(os.path.join(root, "a.md"), "w") as f:
        f.write("clean\n")
    git(root, "add", "a.md")
    git(root, "commit", "-q", "-m", "First import from /Users/someone/work")
    with open(os.path.join(root, "a.md"), "w") as f:
        f.write("still clean\n")
    git(root, "add", "a.md")
    git(root, "commit", "-q", "-m", "second")
    code, out = scan(root, "--public-only")
    check("the root commit's message is scanned by default", code == 1 and "commit" in out)

print("%d failure(s)" % len(failures))
sys.exit(1 if failures else 0)
