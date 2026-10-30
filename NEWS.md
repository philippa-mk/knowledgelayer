# knowledgelayer 0.2.0

## A shared oversight vocabulary

* The package now ships a controlled vocabulary for oversight work
  (`inst/extdata/vocabulary.json`): 47 audit and oversight concepts, 11
  report types, 6 kinds of criteria, a 17-kind findings typology with
  crosswalks to the GAO Green Book, COSO, NIST and other standards, and 63
  program areas (9 top-level clusters and 54 areas within them, reviewed
  row by row). The program areas are starters, meant to be broadly
  applicable; offices add their own with `kl_vocab_import()`. Every crosswalk states its precision and when it was last
  checked against its source. `VOCABULARY.md` in the source says where
  it came from, what was removed, and its license (MIT, as for the code).
* Concepts are identified by short ids such as `ft:noncompliance`. Tags
  store short ids, never URIs, and no web address is built in.
* `kl_vocab()` lists the vocabulary, shipped and local together.
* `kl_resolve()` turns free text into a concept through preferred and
  alternative labels. It never guesses: no match is reported as
  `"no concept"`, and a term matching several concepts as `"ambiguous"`.
* `kl_vocab_extend()` adds an office's own terms in `knowledge/vocabulary.json`,
  layered over the shipped set, which is never edited.
* `kl_vocab_import()` loads an office's program areas from a CSV file
  (`id, prefLabel, altLabels, broader`). Every `broader` must resolve, and
  nothing is imported if any row fails.
* `kl_vocab_check()` reports dangling ids, cycles and duplicate labels.
* `kl_tag()` and `kl_tags()` tag projects, findings and decisions with concepts.
  Terms resolve in context: a finding's tags, like its `typology`, come from
  the findings typology only, and `scheme =` sets the context for others.
* `kl_export_skos()` writes the vocabulary as SKOS Turtle. Its `base`
  argument is required and has no default.

## Changes to existing functions

* `kl_add_project()` gains `concepts =`, and `kl_projects()` a `concepts` column.
* `kl_findings()` gains `typology =`, resolved within the findings
  typology. `kl_read_findings()` and `kl_review_page()` gain `path =`.
* The review page shows each finding's kind and its crosswalks, each
  labeled with its precision. Only a link to an exact item, principle or
  section is presented as a link to that point.
* `kl_find()` searches through synonyms: a term that resolves to a concept
  also matches the concept's other labels (as whole words) and projects
  tagged with it.
* `kl_link()` accepts the SKOS relations `"broader"`, `"narrower"` and
  `"related"` beside the five it had.

## Compatibility

* `projects.json` moves to schema `kl-projects/2` (each project gains a
  `concepts` list). Files from 0.1.0 load unchanged and are upgraded
  automatically the next time the registry is written. A file from a newer
  version is refused, not misread.
* A set of findings with no typology has the same fingerprint as in 0.1.0,
  so a review exported under 0.1.0 still matches its findings.
* The decision log, links and board files are unchanged.

## Build and release

* The R-CMD-check workflow installs R 4.1.3 and Rtools40 on Windows from
  CRAN's archive host, where CRAN moved them, and fails unless the R under test is the
  version the job names. That row takes its packages from a dated 2024
  package-manager snapshot, the last with R 4.1 Windows binaries of every
  dependency.
* Releases are built by a GitHub workflow (`release-tarball`), which fails
  if the tarball's `Packaged:` field names anyone but the GitHub runner.

## Install note

* On R 4.1 under Windows, CRAN no longer serves ready-built packages: the
  README and runbook say how to get `jsonlite` there.

## Fixes

* `inst/review/review-page.html` was missing from the 0.1.0 source import,
  so `kl_review_page()` could not find its template. Restored.

# knowledgelayer 0.1.0

* First release: project registry, links and single points of knowledge;
  the LG Inform Plus capability checklist; the review page, verdict check
  and pipeline gate; the hash-chained decision log; the board.
