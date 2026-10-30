#!/usr/bin/env python3
"""Build inst/extdata/vocabulary.json from constellation-core's taxonomy.

Run from the package root:

    python3 -I data-raw/build_vocab.py --core <path to constellation-core> \
        --ref <commit or branch> --sha256 <expected sha256 of taxonomy.json> \
        --private <private leak config> \
        [--verdicts <APPROVED_program-areas-verdicts_*.json> --proposal <ship-proposal.json>]

The source taxonomy and the private config are the author's and are not
published: users get the built file, which is the complete public record.

The pin is the sha256 of taxonomy.json, not the commit: a merge can change
the commit id but not the file. The build refuses a file whose hash differs.

What it keeps (VOCABULARY.md says why):
  oversight_concepts, report_types, criteria_types, findings_typology (with
  their crosswalks, keeping each one's precision), and program_areas: the
  nine top-level clusters plus only the middle-level areas the program-areas
  review approved. The bottom level never ships.

What it strips: every field on the strip list (STRIP), any label, note or
crosswalk the leak scan flags, any concept whose own label is flagged, the
out-of-scope concepts listed in the private config, every `topConcepts`
list, and every broader/related id that does not ship. A review RENAME
replaces a label outright: the old label is not kept as a synonym.

Without --verdicts the program areas ship as the nine clusters only, marked
in the file as a placeholder. Re-running with --verdicts is the only step
needed once the review is exported. The verdicts and proposal files are read
from wherever they are and never copied into the repository: they list rows
that were held back, and listing those would itself leak.
"""
import argparse
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
spec = importlib.util.spec_from_file_location("leak_scan", os.path.join(HERE, "leak_scan.py"))
leak = importlib.util.module_from_spec(spec)
spec.loader.exec_module(leak)

SCHEMES = ["oversight_concepts", "report_types", "criteria_types", "findings_typology", "program_areas"]
# Scheme labels and descriptions are written here, not copied: core's
# describe its own office and corpus.
SCHEME_TEXT = {
    "oversight_concepts": ("Oversight and Audit Concepts",
                           "Core terminology for government oversight, audit findings and accountability work."),
    "report_types": ("Oversight Report Types",
                     "Kinds of report produced by inspectors general, auditors and similar oversight bodies."),
    "criteria_types": ("Criteria Types",
                       "Kinds of legal and professional standard used as criteria in an audit or review."),
    "findings_typology": ("Findings Typology",
                          "Recurring kinds of deficiency found in oversight work, for grouping findings by "
                          "how things went wrong. Each kind carries crosswalks to the standards it relates "
                          "to, each labeled with how precise its link is."),
    "program_areas": ("Program Areas",
                      "The broad areas of government work an oversight office reviews: top-level clusters, "
                      "and the program areas within them. An office adds its own with kl_vocab_import()."),
}
# Never shipped, whatever their content (the strip list).
STRIP = {"signal_frequency", "corpus_grounding", "provenance", "dc_open_data", "budget_code",
         "pbb_code", "uri_note", "disambiguation", "note", "restored_note", "review_flag",
         "scheme", "topConcepts", "budget_status", "subunit_of", "acronym"}
SHIP_VERDICTS = {"SHIP", "RENAME"}

# Crosswalk check, 2026-10-30 (ruling: verify now, drop the rest). Every
# crosswalk that had "verify" in its label, an unknown precision or no
# verification date was checked against its own source page. Keyed by
# (concept id, uri): a dict replaces label/scheme/precision and stamps the
# date; None drops it. VOCABULARY.md has the table. The build stops if any
# shipped crosswalk is left unverified.
CHECKED = "2026-10-30"
PRECISIONS = {"item", "principle", "section", "scheme", "search"}
NAICS_403 = "census.gov returned 403 to the check; not confirmed, dropped"
CROSSWALK_FIXES = {
    ("concept:civil-society-oversight", "https://nccs.urban.org/nccs/pubs/ntee-two-page-2005.pdf"):
        {"label": "W24 Citizen Participation", "precision": "scheme",
         "checked": "NTEE-CC code list (rev. May 2005) lists W24 Citizen Participation"},
    ("concept:enterprise-risk-management", "https://www.coso.org/erm-framework"):
        {"label": "Enterprise Risk Management\u2014Integrating with Strategy and Performance",
         "precision": "scheme", "checked": "COSO's ERM Framework page names the framework"},
    ("concept:legislative-oversight", "https://www.gov.uk/government/publications/overview-and-scrutiny-statutory-guidance-for-councils-and-combined-authorities"):
        {"scheme": "UK-Statutory-Guidance",
         "label": "Overview and scrutiny: statutory guidance for councils, combined authorities and "
                  "combined county authorities",
         "precision": "scheme", "checked": "the GOV.UK publication page carries this title"},
    ("concept:self-attestation", "https://www.gao.gov/greenbook"):
        {"label": "Standards for Internal Control in the Federal Government (GAO-25-107721)",
         "precision": "scheme",
         "checked": "GAO's Green Book page: the 2025 edition, GAO-25-107721; no single principle"},
    ("concept:single-audit", "https://www.ecfr.gov/current/title-2/subtitle-A/chapter-II/part-200/subpart-F"):
        {"label": "2 CFR part 200, Subpart F\u2014Audit Requirements", "precision": "section",
         "checked": "eCFR's structure API gives Subpart F\u2014Audit Requirements (the HTML page "
                    "sends automated readers to a bot check)"},
    ("report:financial-audit", "https://www.gao.gov/yellowbook"):
        {"label": "Yellow Book: Government Auditing Standards (financial audits)", "precision": "scheme",
         "checked": "GAO's Yellow Book page covers financial and performance audits (2024 revision)"},
    ("report:performance-audit", "https://www.gao.gov/yellowbook"):
        {"label": "Yellow Book: Government Auditing Standards (performance audits)", "precision": "scheme",
         "checked": "GAO's Yellow Book page covers financial and performance audits (2024 revision)"},
    ("ft:it-control-weakness", "https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final"):
        {"label": "SP 800-53 Rev. 5: Security and Privacy Controls for Information Systems and "
                  "Organizations", "precision": "scheme",
         "checked": "NIST CSRC publication page; links the whole catalog, not one control family"},
    ("concept:fleet-management", "https://www.gao.gov/products/gao-14-704g"): None,
    # Gate review, 2026-10-30: three links claimed more precision than they have.
    ("ft:improper-payments", "https://www.congress.gov/116/plaws/publ117/PLAW-116publ117.pdf"):
        {"label": "Payment Integrity Information Act of 2019 (Public Law 116-117)", "precision": "scheme",
         "checked": "the link is the whole act; Appendix C to OMB A-123 is a separate document"},
    ("ft:fraud-misappropriation", "https://www.acfe.com/acfe-insights-blog/blog-detail?s=fraud-tree-explained"):
        {"label": "The Fraud Tree Explained: Classifying Occupational Fraud Risks (ACFE)",
         "precision": "scheme", "checked": "an ACFE article on the whole Fraud Tree"},
    ("ft:eligibility-error", "https://www.whitehouse.gov/wp-content/uploads/2021/03/M-21-19.pdf"):
        {"label": "OMB M-21-19: Appendix C to OMB Circular A-123, Requirements for Payment Integrity "
                  "Improvement", "precision": "scheme",
         "checked": "the link is the whole memorandum, not one section"},
}
# Crosswalks added by the check: the second half of a label that cited two
# documents, given its own link.
CROSSWALK_ADD = {
    "ft:improper-payments": [
        {"type": "relatedMatch", "scheme": "OMB-A-123-C",
         "label": "OMB M-21-19: Appendix C to OMB Circular A-123, Requirements for Payment Integrity "
                  "Improvement",
         "uri": "https://www.whitehouse.gov/wp-content/uploads/2021/03/M-21-19.pdf",
         "precision": "scheme", "verified": CHECKED},
    ],
}
CROSSWALK_DROP_REASON = {
    ("concept:fleet-management", "https://www.gao.gov/products/gao-14-704g"):
        "the page is the 2014 Green Book, marked superseded by GAO-25-107721",
}


def fix_crosswalk(cid, m, b):
    """Apply the 2026-10-30 check to one crosswalk; None means drop it."""
    key = (cid, m["uri"])
    if key in CROSSWALK_FIXES:
        fix = CROSSWALK_FIXES[key]
        if fix is None:
            b.note("%s: crosswalk dropped (%s)" % (cid, CROSSWALK_DROP_REASON[key]))
            return None
        m = dict(m, **{k: v for k, v in fix.items() if k != "checked"})
        m["verified"] = CHECKED
        return m
    if m["uri"].startswith("https://www.census.gov/naics/"):
        b.note("%s: crosswalk dropped (%s)" % (cid, NAICS_403))
        return None
    return m


# Some concepts ship under ids that differ from the source's, and a few
# synonyms are removed; both are listed only in the private config
# ("id_map", "remove_altLabels"), so no public file names a source id.

# Local edits on top of core: small changes made in this package, each
# answering a note from the program-areas review (2026-10-30). Applied after
# the verdicts, and only to concepts that ship. VOCABULARY.md lists them, and
# the built file records them under "local_edits".
LOCAL_EDITS = [
    {"id": "cluster:human-services",
     "scopeNote": "Services delivered to residents: income support, child welfare, disability "
                  "services, aging, homelessness and similar programs. Not human resources: a "
                  "government's own staffing and personnel work is under Personnel & HR "
                  "(concept:personnel-hr), in the cross-cutting cluster.",
     "why": "Note 1: read as distinct from human resources."},
    {"id": "concept:personnel-hr",
     "scopeNote": "A government's own workforce: hiring, classification, pay, discipline and "
                  "personnel records. Internal operations, not the human services delivered to "
                  "residents (cluster:human-services).",
     "why": "Note 1, the other side: human resources read as internal operations."},
    {"id": "concept:public-health",
     "add_altLabels": ["disease prevention", "health promotion"],
     "scopeNote": "Population-level health programs: disease prevention and surveillance, health "
                  "promotion, environmental health and the health department's regulatory work. "
                  "Individual treatment programs, such as mental health or substance use, have "
                  "their own areas.",
     "why": "Note 2: a large clustering point, so its synonyms and definition say what it covers."},
    {"id": "concept:lead-poisoning",
     "add_related": ["concept:public-health", "concept:water-quality"],
     "why": "Note 3: clusters with public health and with water, so related links to both; "
            "broader unchanged."},
    {"id": "concept:dd-waiver",
     "prefLabel": "Developmental Disabilities (DD) Medicaid Waiver",
     "add_altLabels": ["DD Medicaid Waiver", "developmental disabilities waiver"],
     "scopeNote": "DD stands for developmental disabilities. A Medicaid home and community-based "
                  "services (HCBS) waiver that pays for services for people with intellectual and "
                  "developmental disabilities in their homes and communities rather than in an "
                  "institution.",
     "why": "Note 4: spell out what DD means; \"DD waiver\" kept as a synonym."},
    {"id": "concept:developmental-disabilities",
     "remove_altLabels": ["DD waiver"],
     "why": "Note 4, so that \"DD waiver\" names the waiver alone: on both concepts it would be "
            "ambiguous and the build would remove it from both."},
    # Neutral public-administration wording (gate review, 2026-10-30).
    {"id": "concept:executive-management-of-agencies",
     "prefLabel": "Executive Management of Agencies",
     "set_altLabels": ["executive control of agencies", "agency reorganization",
                       "political appointments", "executive orders and directives"],
     "scopeNote": "How elected executives direct agencies: appointments, reorganization, budgets "
                  "and administrative directives.",
     "why": "Neutral public-administration wording."},
    {"id": "concept:checks-and-balances",
     "prefLabel": "Checks and Balances",
     "set_altLabels": ["separation of powers", "institutional safeguards", "democratic governance",
                       "rule of law", "institutional resilience"],
     "scopeNote": "The constitutional and statutory arrangements that let one part of government "
                  "check another: legislative oversight, independent audit and inspection, courts.",
     "why": "Neutral public-administration wording."},
    {"id": "concept:oversight-independence",
     "prefLabel": "Independence of Oversight Offices",
     "set_altLabels": ["IG independence", "auditor independence", "organizational independence",
                       "oversight capacity", "inspector general capacity"],
     "scopeNote": "The organizational independence and resources an audit or oversight office "
                  "needs to report without interference, as auditing standards require.",
     "why": "Neutral public-administration wording."},
]


def check_renames(vocab, renamed_from, id_map, remove_alt):
    """A renamed label, a replaced id and a removed synonym must be gone."""
    labels = {leak.name_key(x) for k in vocab["concepts"]
              for x in [k["prefLabel"]] + k["altLabels"]}
    for old in renamed_from:
        if leak.name_key(old) in labels:
            sys.exit("STOP: the renamed label %r still ships" % old)
    by_id = {k["id"]: k for k in vocab["concepts"]}
    for cid, gone in remove_alt.items():
        left = {a.lower() for a in by_id.get(cid, {}).get("altLabels", [])} & {a.lower() for a in gone}
        if left:
            sys.exit("STOP: %d removed synonym(s) still on %s" % (len(left), cid))
    text = json.dumps(vocab)
    for old in id_map:
        if '"%s"' % old in text:
            sys.exit("STOP: the replaced id %s still ships" % old)


def rename_ids(out, id_map, remove_alt):
    for k in out:
        k["id"] = id_map.get(k["id"], k["id"])
        for rel in ("broader", "related"):
            k[rel] = [id_map.get(x, x) for x in k[rel]]
        drop = {a.lower() for a in remove_alt.get(k["id"], [])}
        k["altLabels"] = [a for a in k["altLabels"] if a.lower() not in drop]


def apply_local_edits(out, b):
    by_id = {k["id"]: k for k in out}
    applied = []
    for e in LOCAL_EDITS:
        k = by_id.get(e["id"])
        if k is None:
            continue
        for field in ("prefLabel", "scopeNote"):
            if field in e:
                k[field] = e[field]
        if "set_altLabels" in e:
            k["altLabels"] = list(e["set_altLabels"])
        drop = {a.lower() for a in e.get("remove_altLabels", [])}
        k["altLabels"] = [a for a in k["altLabels"] if a.lower() not in drop]
        for a in e.get("add_altLabels", []):
            if a.lower() not in {x.lower() for x in k["altLabels"]}:
                k["altLabels"].append(a)
        k["altLabels"] = [a for a in k["altLabels"] if a.lower() != k["prefLabel"].lower()]
        for r in e.get("add_related", []):
            if r in by_id and r not in k["related"]:
                k["related"].append(r)
                if k["id"] not in by_id[r]["related"]:
                    by_id[r]["related"].append(k["id"])
        for text in [k["prefLabel"], k["scopeNote"]] + k["altLabels"]:
            if b.flagged(text):
                sys.exit("STOP: local edit to %s fails the leak scan" % k["id"])
        applied.append({"id": e["id"], "why": e["why"]})
    return applied
KNOWN_VERDICTS = {"SHIP", "RENAME", "HOLD", "DROP"}


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def as_list(x):
    if x is None:
        return []
    return [x] if isinstance(x, str) else list(x)


def concepts_of(scheme):
    cs = scheme["concepts"]
    return list(cs.values()) if isinstance(cs, dict) else cs


class Build:
    def __init__(self, rules):
        self.rules = rules
        self.log = []

    def flagged(self, s):
        hits = leak.scan_text(s, self.rules)
        hits += [(m.group(0), "URI") for m in leak.URI.finditer(s)]
        return hits

    def note(self, what):
        self.log.append(what)

    def labels(self, cid, labels, pref, strict=False):
        out, seen = [], {pref.lower()}
        for a in as_list(labels):
            if self.flagged(a):
                if strict:
                    sys.exit("STOP: approved row %s has a flagged altLabel" % cid)
                self.note("%s: altLabel stripped by the leak scan" % cid)
            elif a.lower() not in seen:
                seen.add(a.lower())
                out.append(a)
        return out

    def mappings(self, cid, maps):
        out = []
        for m in as_list(maps):
            uri = m.get("uri") or ""
            text_hits = self.flagged(m.get("label") or "") + self.flagged(m.get("scheme") or "")
            uri_hits = leak.scan_text(uri, self.rules)
            if text_hits or uri_hits or not re.match(r"^https?://", uri):
                self.note("%s: crosswalk stripped by the leak scan" % cid)
                continue
            m = fix_crosswalk(cid, {"type": m["type"], "scheme": m["scheme"], "label": m["label"],
                                    "uri": uri, "precision": m.get("uri_precision") or "unknown",
                                    "verified": m.get("uri_verified_at") or ""}, self)
            if m is None:
                continue
            if m["precision"] not in PRECISIONS or not m["verified"] or "verify" in m["label"].lower():
                sys.exit("STOP: %s has an unverified crosswalk to %s" % (cid, m["uri"]))
            out.append(m)
        out += [dict(m) for m in CROSSWALK_ADD.get(cid, [])]
        return out

    def concept(self, c, scheme, strict=False):
        cid, pref = c["id"], c["prefLabel"]
        if self.flagged(pref):
            if strict:
                sys.exit("STOP: approved row %s has a flagged label; surface it, do not strip it" % cid)
            self.note("%s: whole concept dropped (its label is flagged)" % cid)
            return None
        note = c.get("scopeNote") or c.get("scope_note") or c.get("definition") or ""
        if note and self.flagged(note):
            if strict:
                sys.exit("STOP: approved row %s has a flagged definition" % cid)
            self.note("%s: scopeNote stripped by the leak scan" % cid)
            note = ""
        alts = self.labels(cid, c.get("altLabels"), pref, strict)
        return {"id": cid, "scheme": scheme, "prefLabel": pref, "altLabels": alts,
                "broader": as_list(c.get("broader")), "related": as_list(c.get("related")),
                "scopeNote": note,
                "mappings": self.mappings(cid, c.get("skos_mappings") or c.get("mappings"))}


def dedupe_labels(out, b):
    """One label, one concept, within a scheme, so kl_resolve() can answer.

    Core uses a narrower concept's name as a synonym of its broader one
    ("performance audit" under Audit). Within a scheme: a label that is some
    concept's prefLabel is removed as an altLabel elsewhere; an altLabel on
    several concepts stays only on the one that is narrower than all the
    others, and if there is none, it is removed from all of them. Labels
    shared across schemes are kept: kl_resolve(scheme =) tells them apart.
    """
    by_id = {k["id"]: k for k in out}

    def ancestors(cid):
        seen, stack = set(), list(by_id[cid]["broader"])
        while stack:
            x = stack.pop()
            if x not in seen and x in by_id:
                seen.add(x)
                stack += by_id[x]["broader"]
        return seen

    for scheme in SCHEMES:
        ks = [k for k in out if k["scheme"] == scheme]
        prefs = {k["prefLabel"].lower(): k["id"] for k in ks}
        for k in ks:
            keep = [a for a in k["altLabels"] if prefs.get(a.lower(), k["id"]) == k["id"]]
            if len(keep) != len(k["altLabels"]):
                b.note("%s: altLabel removed, it is another concept's prefLabel" % k["id"])
            k["altLabels"] = keep
        holders = {}
        for k in ks:
            for a in k["altLabels"]:
                holders.setdefault(a.lower(), []).append(k["id"])
        for label, ids in holders.items():
            if len(ids) < 2:
                continue
            narrowest = [i for i in ids if all(j == i or j in ancestors(i) for j in ids)]
            for i in ids:
                if narrowest and i == narrowest[0]:
                    continue
                by_id[i]["altLabels"] = [a for a in by_id[i]["altLabels"] if a.lower() != label]
                b.note("%s: shared altLabel removed (%s)" % (
                    i, "kept on the narrower concept" if narrowest else "no concept is narrower"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--core", required=True)
    ap.add_argument("--ref", required=True)
    ap.add_argument("--sha256", required=True)
    ap.add_argument("--verdicts")
    ap.add_argument("--proposal")
    ap.add_argument("--private", required=True,
                    help="the private leak config: rules, allow-list, out-of-scope concepts")
    args = ap.parse_args()
    if bool(args.verdicts) != bool(args.proposal):
        sys.exit("--verdicts and --proposal go together")

    raw = subprocess.run(["git", "-C", args.core, "show", args.ref + ":data/taxonomy/taxonomy.json"],
                         capture_output=True, check=True).stdout
    if sha256(raw) != args.sha256:
        sys.exit("taxonomy.json at %s has sha256 %s, not the pinned %s" % (args.ref, sha256(raw), args.sha256))
    commit = subprocess.run(["git", "-C", args.core, "rev-parse", args.ref], capture_output=True,
                            text=True, check=True).stdout.strip()
    tax = json.loads(raw)

    with open(args.private, encoding="utf-8") as f:
        private = json.load(f)
    drop_concepts = set(private.get("drop_concepts", []))
    b = Build(leak.Rules(private, tax))

    out = []
    for scheme in SCHEMES[:4]:
        for c in concepts_of(tax["schemes"][scheme]):
            if c["id"] in drop_concepts:
                b.note("%s: left out (out of scope)" % c["id"])
                continue
            k = b.concept(c, scheme)
            if k:
                out.append(k)

    clusters = {"cluster:" + key: {"id": "cluster:" + key, "prefLabel": cl["label"],
                                   "altLabels": cl.get("altLabels", [])}
                for key, cl in tax["clusters"].items()}
    middle_note = None
    renamed_from = []
    source_review = None
    if args.verdicts:
        with open(args.verdicts, "rb") as f:
            vraw = f.read()
        v = json.loads(vraw)
        if v.get("schema") != "approved-set/1.0":
            sys.exit("not an approved-set/1.0 export: " + args.verdicts)
        with open(args.proposal, encoding="utf-8") as f:
            rows = {r["export_key"]: r for r in json.load(f)["rows"]}
        verdicts = {}
        for key, it in v["items"].items():
            if it.get("verdict") not in KNOWN_VERDICTS:
                sys.exit("unknown verdict %r for %s" % (it.get("verdict"), key))
            if key not in rows or rows[key]["id"] != it.get("refId"):
                sys.exit("verdict %s does not match a proposal row" % key)
            verdicts[key] = it
        missing = set(rows) - set(verdicts)
        if missing:
            sys.exit("%d proposal rows have no verdict; the export is incomplete" % len(missing))
        for n in v.get("notes", {}).values():
            if n.strip():
                b.note("reviewer note present: read the export's notes by hand (not parsed)")
                break
        shipped_pa = []
        renamed_from = []
        for key in sorted(rows):
            r, it = rows[key], verdicts[key]
            if it["verdict"] not in SHIP_VERDICTS:
                continue
            r = dict(r)
            if it["verdict"] == "RENAME":
                # A rename replaces the label; the old one is not kept as a synonym.
                new = it.get("optionText") or it.get("option")
                old = r["prefLabel"]
                renamed_from.append(old)
                r["altLabels"] = [a for a in as_list(r.get("altLabels"))
                                  if a.lower() not in (new.lower(), old.lower())]
                r["prefLabel"] = new
            if r.get("level") == "cluster":
                r["broader"] = None
            k = b.concept(r, "program_areas", strict=True)
            shipped_pa.append(k)
        out += shipped_pa
        n_mid = sum(1 for k in shipped_pa if not k["id"].startswith("cluster:"))
        source_review = {"review": v.get("review", ""), "exportedAt": v.get("exportedAt", ""),
                         "sha256": sha256(vraw), "shipped": len(shipped_pa), "middle_level": n_mid}
    else:
        for cid in sorted(clusters):
            out.append(b.concept(clusters[cid], "program_areas"))
        middle_note = ("PLACEHOLDER: the middle-level program areas await the program-areas review. "
                       "Until its export is applied, only the top-level clusters ship, under core's labels. "
                       "Re-run data-raw/build_vocab.py with --verdicts to apply it.")

    rename_ids(out, private.get("id_map", {}), private.get("remove_altLabels", {}))
    local_edits = apply_local_edits(out, b)
    ids = {k["id"] for k in out}
    for k in out:
        for rel in ("broader", "related"):
            keep = [x for x in k[rel] if x in ids and x != k["id"]]
            if len(keep) != len(k[rel]):
                b.note("%s: %d %s id(s) dropped (not shipped)" % (k["id"], len(k[rel]) - len(keep), rel))
            k[rel] = keep
    for k in out:
        k["narrower"] = sorted(c["id"] for c in out if k["id"] in c["broader"])
    dedupe_labels(out, b)
    order = {s: i for i, s in enumerate(SCHEMES)}
    out.sort(key=lambda k: (order[k["scheme"]], k["id"]))
    for k in out:
        assert not ((set(k) - {"scheme"}) & STRIP), k["id"]

    vocab = {
        "schema": "kl-vocabulary/1",
        "source": {"name": "constellation-core", "file": "data/taxonomy/taxonomy.json",
                   "version": tax["_meta"]["version"], "sha256": args.sha256, "commit": commit},
        "program_areas_review": source_review,
        "placeholder": middle_note,
        "local_edits": local_edits,
        "license": "MIT, the same as the package code (see LICENSE). Crosswalk targets are cited "
                   "by name and link only.",
        "schemes": {s: {"label": SCHEME_TEXT[s][0], "description": SCHEME_TEXT[s][1]} for s in SCHEMES},
        "concepts": [{key: k[key] for key in ("id", "scheme", "prefLabel", "altLabels", "broader",
                                              "narrower", "related", "scopeNote", "mappings")}
                     for k in out],
    }
    check_renames(vocab, renamed_from, private.get("id_map", {}), private.get("remove_altLabels", {}))
    hits = leak.scan_vocab(vocab, b.rules)
    if hits:
        for h in hits:
            print("LEAK", h)
        sys.exit("STOP: the built vocabulary fails the leak scan")
    dest = os.path.join(ROOT, "inst/extdata/vocabulary.json")
    with open(dest, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False, indent=1)
        f.write("\n")
    counts = {}
    for k in out:
        counts[k["scheme"]] = counts.get(k["scheme"], 0) + 1
    print("core %s (sha256 %s, commit %s)" % (tax["_meta"]["version"], args.sha256, commit[:7]))
    print("shipped:", json.dumps(counts))
    print("stripped (%d):" % len(b.log))
    for line in b.log:
        print("  " + line)


if __name__ == "__main__":
    main()
