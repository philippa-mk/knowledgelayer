# The shared oversight vocabulary

`inst/extdata/vocabulary.json` is a controlled vocabulary for oversight
work, shipped with knowledgelayer from version 0.2.0. Read it in R with
`kl_vocab()`. This note says where it came from, what was changed on the
way, and how it is licensed.

## Where it came from

The vocabulary is built from the author's own taxonomy, constellation-core,
which is private, by `data-raw/build_vocab.py`. The build is pinned by the
SHA-256 of the source file, not by a commit, because a merge can change the
commit id but never the file. The script refuses any file whose hash differs
from the pin, which lets the author prove what a given build was made from.

| | |
|---|---|
| Source | constellation-core, `data/taxonomy/taxonomy.json` |
| Version | 0.18.1 |
| SHA-256 (the pin) | `3ad05b0a5ba066fe662b73fc1629d8429bed4af3efcc796811cde82de08f994e` |
| Commit when built | `81b4cea` |
| Program-areas review | `program-areas-2026-10-30-knowledgelayer`, exported 2026-10-30 |
| Review export SHA-256 | `262811d3e1f905c8a579eb62c48b5cee1140adf2e07d4e3488afa614dab0b77f` |

The same values are in the file's `source` and `program_areas_review`
fields, and the source in `attr(kl_vocab(), "source")`.

## What is in it

| Scheme | Concepts | What it is |
|---|---|---|
| `oversight_concepts` | 47 | Audit, inspection, evaluation, internal control, fraud, governance and related terms |
| `report_types` | 11 | Kinds of oversight report |
| `criteria_types` | 6 | Kinds of criteria: law, regulation, policy, standards |
| `findings_typology` | 17 | Recurring kinds of deficiency, with crosswalks to the standards |
| `program_areas` | 63 | 9 top-level clusters and 54 program areas within them |

**The program areas are starters.** The broad clusters and the program areas
under them are meant to be broadly applicable, but they may not fit every
office perfectly. Some, such as Medicaid, TANF, a paid family leave program
or lottery regulation, are typically run by states or counties: an office
that does not oversee them can ignore them. Every office adds its own with
`kl_vocab_import()`, under the clusters, in its own local layer.

The source has three levels of program area. The nine top-level clusters
ship. The middle level shipped only after a row-by-row review by the author
on 2026-10-30: 58 shipped as shown, 5 were renamed, and 1 was left out. A
rename replaces the label outright. The bottom level does not ship.

Out-of-scope report types were left out. So were the source's schemes of
agencies, budget units and funds, which describe one jurisdiction, and its
civic resources, which are not needed here.

## What was changed on the way, and why

Removed from every concept, whatever it says:

- **Corpus counts** (`signal_frequency`, `corpus_grounding`). These were hit
  counts over the source's own report collection: a triage signal that reads
  as evidence.
- **Provenance and notes** (`provenance`, `note`, `restored_note`,
  `review_flag`, `uri_note`, `disambiguation`). These record working history
  and internal codes.
- **Jurisdiction data fields** (open-data records and budget codes).
- **Every cluster's `topConcepts`**, which listed the source's agencies.

The scheme labels and descriptions are written fresh by the build, because
the source's describe its own collection.

Then a leak check runs on every remaining string. It has two parts. The
public part looks for local paths, e-mail addresses, account names, hosting
namespaces and URIs outside a crosswalk; it runs in the package's own tests
and in CI on every change. The other part looks for names specific to the
source's jurisdiction. Its rules are kept with the private source and are
not published, because they would themselves name it; they include a short,
reviewed allow-list of generic national terms that happen to share a name.
That maintainer-side check runs before each release, over every file and
every commit message. Anything the check flags is removed: a whole concept if its own label
is flagged, otherwise just the flagged synonym, definition or crosswalk. In
this build that was 2 concepts, 14 synonyms, 2 definitions and 7 crosswalks.

So that a term search gives one answer, a label is never on two concepts in
the same scheme. A label that is one concept's preferred name is removed as
a synonym of another. A synonym on several concepts stays only on the
narrowest of them, and if none is narrower than the rest, it is removed from
all of them (18 removals in this build). Labels shared across schemes are
kept, such as "audit" the activity and "audit" the report;
`kl_resolve(scheme = )` tells them apart, and `kl_vocab_check()` lists them
as warnings.

Broader and related ids that point at anything not shipped are dropped.
Narrower lists are derived from broader.

## Identifiers that differ from the source

A few concepts ship under ids different from the source's. Everything that
pointed at them uses the shipped id.

## Local edits on top of core

Small changes made in this package, not in the source. The build applies
them after the review's verdicts and records each in the file's
`local_edits` field.

| Concept | Edit | Why |
|---|---|---|
| `cluster:human-services` | Definition added: services delivered to residents, not human resources. No synonym suggests staffing. | Read as distinct from human resources. |
| `concept:personnel-hr` | Definition added: a government's own workforce, internal operations, not human services. | The same, from the other side. |
| `concept:public-health` | Synonyms "disease prevention" and "health promotion" added, and a definition of what it covers. | Likely to be a large clustering point. |
| `concept:lead-poisoning` | Broader unchanged (Health); related to `concept:public-health` and `concept:water-quality`, both ways. | Could cluster under public health or public utilities. |
| `concept:dd-waiver` | Renamed "Developmental Disabilities (DD) Medicaid Waiver", with a definition that says what DD means; "DD waiver" kept as a synonym. | Define what DD means. |
| `concept:developmental-disabilities` | Synonym "DD waiver" removed, so it names the waiver alone. | On both concepts it would be ambiguous. |
| `concept:executive-management-of-agencies` | Relabeled "Executive Management of Agencies", with plain synonyms and a definition. | Neutral public-administration wording. |
| `concept:checks-and-balances` | Relabeled "Checks and Balances", with plain synonyms and a definition. | Neutral public-administration wording. |
| `concept:oversight-independence` | Relabeled "Independence of Oversight Offices", with plain synonyms and a definition. | Neutral public-administration wording. |

## Crosswalks

The findings typology and many concepts carry crosswalks to the standards
they relate to: the GAO Green Book and Yellow Book, COSO, NIST SP 800-53,
OMB guidance, CIGIE, INTOSAI, AICPA, ACFE and others. They are **cited by
name and link only**: no text of any standard is reproduced.

Each crosswalk keeps its **precision**: whether its link goes to the exact
`item`, `principle` or `section`, to the whole standard (`scheme`), or to a
`search`. Only an exact link is presented as a link to the point itself. The
review page says "link to the whole standard, not to this point" for the
others, and `kl_export_skos()` writes them as `rdfs:seeAlso`, not as SKOS
matches.

Every shipped crosswalk has a stated precision and a date it was checked;
the build stops otherwise, and a test fails. On 2026-10-30 every crosswalk
whose label said "verify", whose precision was unknown or which had never
been checked was checked against its own source page, and three that
claimed more precision than their link has were corrected:

| Concept | Link checked | What the source said | Result |
|---|---|---|---|
| `concept:civil-society-oversight` | nccs.urban.org NTEE-CC code list (2005) | W24 Citizen Participation | Kept, relabeled; precision scheme (the whole list) |
| `concept:enterprise-risk-management` | coso.org/erm-framework | Enterprise Risk Management—Integrating with Strategy and Performance | Kept; precision scheme |
| `concept:legislative-oversight` | gov.uk overview and scrutiny statutory guidance | Overview and scrutiny: statutory guidance for councils, combined authorities and combined county authorities | Kept, relabeled; scheme renamed UK-Statutory-Guidance; precision scheme |
| `concept:self-attestation` | gao.gov/greenbook | Standards for Internal Control in the Federal Government, 2025 edition (GAO-25-107721) | Kept, relabeled (it named no single principle); precision scheme |
| `concept:single-audit` | eCFR 2 CFR part 200, subpart F | Subpart F—Audit Requirements (read through eCFR's structure API; the page itself sends automated readers to a bot check) | Kept, relabeled; precision section |
| `report:financial-audit` | gao.gov/yellowbook | Yellow Book: Government Auditing Standards, 2024 revision, covering financial and performance audits | Kept, relabeled; precision scheme |
| `report:performance-audit` | gao.gov/yellowbook | As above | Kept, relabeled; precision scheme |
| `ft:it-control-weakness` | csrc.nist.gov SP 800-53 Rev. 5 | Security and Privacy Controls for Information Systems and Organizations (the whole catalog, not one family) | Kept, relabeled; precision scheme |
| `ft:improper-payments` | congress.gov Public Law 116-117 | The Payment Integrity Information Act of 2019, the whole act | Kept, relabeled; precision scheme (was item). Its label also cited OMB Circular A-123 Appendix C, which is a separate document, so that is now its own crosswalk, to OMB M-21-19 |
| `ft:fraud-misappropriation` | acfe.com, "The Fraud Tree Explained" | An article on the whole Fraud Tree | Kept, relabeled; precision scheme (was item) |
| `ft:eligibility-error` | whitehouse.gov, OMB M-21-19 | Transmittal of Appendix C to OMB Circular A-123, the whole memorandum | Kept, relabeled; precision scheme (was section) |
| `concept:fleet-management` | gao.gov/products/gao-14-704g | The 2014 Green Book, marked superseded by GAO-25-107721 | Dropped |
| 12 program areas and concepts with NAICS 2022 links | census.gov/naics | The site returned 403 to the check | Dropped, not confirmed |

## Identifiers: short ids, and no web address

Concepts are identified by short ids such as `ft:fraud-misappropriation`.
**The short ids are the stable identifiers.** Tags store them, never a URI.

No base URI is built in anywhere: no hosting path, no domain. A concept is
given a web address only when someone exports it, with
`kl_export_skos(file, base)`, and `base` is required, with no default.
Whoever exports chooses the namespace. If the vocabulary is later given
permanent web names, a later version can adopt them as a default, and
nothing anyone has tagged changes, because tags hold short ids. The only
URIs in the file are the crosswalk links, in each crosswalk's `uri` field,
and a test fails on a URI anywhere else.

## License

MIT, the same as the package code: see `LICENSE`. The package's single
license covers the shipped vocabulary. Because the crosswalk targets are
cited by name and link and never reproduced, no third-party license is
involved.

## Rebuilding

Only the author can rebuild the vocabulary: the build reads the private
source taxonomy, the program-areas review and the private leak rules, none
of which is published. Everyone else gets the built file,
`inst/extdata/vocabulary.json`, which is the complete public record of what
ships. For the author:

```bash
python3 -I data-raw/build_vocab.py --core <source checkout> --ref <commit> \
  --sha256 <pinned sha256> --private <private leak rules> \
  --verdicts <program-areas export> --proposal <program-areas proposal>
python3 -I data-raw/leak_scan.py --private <private leak rules> \
  --core <source checkout> --ref <commit> --history <commit range>
```

`data-raw/leak_scan.py --public-only` runs the public rules on their own,
and says that the jurisdiction check did not run.
