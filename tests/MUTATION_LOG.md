# Mutation log, knowledgelayer 0.2.0

Excluded from the package build (`.Rbuildignore`). Each new safeguard was
broken on purpose, one at a time, and the test file that guards it was run
against the broken code (`pkgload::load_all()` + `testthat::test_file()`).
A safeguard counts as covered only if at least one test went red. Each
mutation was then reverted with `git checkout -- <file>`, and the file's
bytes were compared with the original.

Run 2026-10-30, R 4.6.2 (macOS, x86_64 build), on commit `2380345` of
`claude/v0-2-build-27e190`. Every mutation carried a `MUTANT-<id>` marker so
that its restoration could be proved by search.

| Id | Safeguard | File broken | The break | Guarding tests | Failures | Restored |
|---|---|---|---|---|---|---|
| M1 | `kl_resolve()` never guesses | `R/vocab.R` | an ambiguous term takes its first candidate | test-vocab.R | 6 | yes |
| M2 | Layering: the shipped set is never redefined | `R/vocab.R` | the shipped-id clash check is skipped | test-vocab.R | 1 | yes |
| M3 | Migration: `kl-projects/1` is upgraded to `/2` | `R/registry.R` | the registry stays at `/1` after a write | test-vocab.R | 1 | yes |
| M4 | Migration: a newer schema is refused | `R/registry.R` | the refusal is removed | test-vocab.R | 1 | yes |
| M5 | Migration: a v0.1 findings set keeps its fingerprint | `R/review.R` | the empty typology column is hashed | test-vocab.R | 2 | yes |
| M6 | Leak scan: the plain rules are applied | `tests/testthat/helper-leak.R` | the rule loop runs zero times | test-leak.R | 5 | yes |
| M7 | Leak scan: agency names matched by hash | `tests/testthat/helper-leak.R` | name n-grams never match | test-leak.R | 1 | yes |
| M8 | Leak scan: the shipped vocabulary is scanned | `inst/extdata/vocabulary.json` | a planted place name in a label | test-leak.R | 2 | yes |
| M9 | Leak scan: only the exact credit line is allowed | `tests/testthat/helper-leak.R` | the abbreviation is allowed everywhere | test-leak.R | 2 | yes |
| M10 | Precision labeling: `scheme` is never shown as exact | `R/vocab.R` | `scheme` added to the exact precisions | test-vocab.R | 4 | yes |
| M11 | Import validation: every `broader` must resolve | `R/vocab.R` | the dangling-id check is skipped | test-vocab.R | 3 | yes |
| M12 | Import validation: a program area needs a `broader` | `R/vocab.R` | the check is skipped | test-vocab.R | 1 | yes |
| M13 | Export: `base` is required, with no default | `R/vocab.R` | `base` given a default, check bypassed | test-vocab.R | 2 | yes |
| M14 | No URI: local ids must be short ids | `R/vocab.R` | the id pattern accepts anything | test-vocab.R | 1 | yes |
| M15 | No URI in the shipped vocabulary outside crosswalks | `inst/extdata/vocabulary.json` | a URI planted in a definition | test-leak.R | 1 | yes |
| M16 | No URI in tags | `R/vocab.R` | `kl_tag()` stores terms without resolving | test-leak.R | 3 | yes |
| P1 | Leak scan script catches a leak in the tree | `NEWS.md` | a planted place name | `data-raw/leak_scan.py` | exit 1 | yes |
| P2 | The shared rules file drives both scanners | `tests/testthat/fixtures/leak-rules.tsv` | a place-name rule replaced | test-leak.R | 1 | yes |

After all were restored: test-vocab.R 0 failures, test-leak.R 0 failures,
`git status` clean, and

```
$ /usr/bin/grep -r "MUTANT" --exclude-dir=.git --exclude=MUTATION_LOG.md .
$ echo $?
1
```

No marker anywhere in the tree except this log, which names it.

Not mutated: the v0.1 safeguards, whose mutation record is in the v0.1
gate record, and whose tests still pass unchanged (`test-knowledgelayer.R`).

## Second run, 2026-10-30: rulings, verdicts and the allow-list

On commit `0a05071`, after the program-areas verdicts, the four local edits,
the crosswalk check and the allow-list. Mutations marked "rebuild" were made
in the build script; the vocabulary was rebuilt and the test run on the
result. A build that stopped on its own gate also counts as caught.

| Id | Safeguard | File broken | The break | Caught by | Result | Restored |
|---|---|---|---|---|---|---|
| M17 | Crosswalks: precision stated | `inst/extdata/vocabulary.json` | one crosswalk's precision set to `unknown` | test-vocab.R | 1 failure | yes |
| M18 | Crosswalks: no "verify" label ships | `inst/extdata/vocabulary.json` | "(verify code)" put back on a label | test-vocab.R | 1 failure | yes |
| M19 | Allow-list: removing a term restores the block | `tests/testthat/fixtures/leak-allow.tsv` | OPEB taken off the list | test-leak.R | 4 failures | yes |
| M20 | Allow-list: nothing beyond the three terms | `tests/testthat/fixtures/leak-allow.tsv` | an agency acronym added to the list | test-leak.R | 3 failures | yes |
| M21 | Local edit: DD spelled out (rebuild) | `data-raw/build_vocab.py` | the waiver's new label removed | test-vocab.R | 1 failure | yes |
| M22 | An out-of-scope concept stays out (rebuild) | `data-raw/build_vocab.py` | the drop removed | the build's crosswalk gate | build stopped | yes |
| M22b | The same, at the test | `inst/extdata/vocabulary.json` | the concept put back in the file | test-vocab.R | 2 failures | yes |
| M23 | Local edit: lead poisoning related to both (rebuild) | `data-raw/build_vocab.py` | the water-quality link removed | test-vocab.R | 2 failures | yes |
| P3 | Allow-list: the build stops without it | `tests/testthat/fixtures/leak-allow.tsv` | OPEB taken off the list | `data-raw/build_vocab.py` | build stopped on `concept:pension` | yes |

All restored: test-vocab.R and test-leak.R 0 failures, `git status` clean,
and the same `grep -r "MUTANT"` search exits 1.

## Third run, 2026-10-30: resolve by context

On commit `360c667`.

| Id | Safeguard | File broken | The break | Caught by | Result | Restored |
|---|---|---|---|---|---|---|
| M24 | A finding's kind resolves in the findings typology | `R/vocab.R` | the context for findings removed | test-vocab.R | 2 failures | yes |
| M25 | `kl_tag()` honors the context | `R/vocab.R` | `kl_tag()` resolves across every scheme | test-vocab.R | 1 failure | yes |

Restored byte for byte (`cmp`), test-vocab.R 0 failures, and the `grep -r
"MUTANT"` search exits 1.

## Fourth run, 2026-10-30: the gate review's fixes

On commit `9230f57`. The leak check's source-specific rules moved out of
the repository (the earlier runs' `tests/testthat/fixtures/` files and the
hashed name list no longer exist); the scanner now has its own self-test,
`data-raw/test_leak_scan.py`, with an invented city. One mutation was made
in the private config, outside the repository, and restored from a copy.

| Id | Safeguard | File broken | The break | Caught by | Result | Restored |
|---|---|---|---|---|---|---|
| M26 | A review rename replaces the label | `data-raw/build_vocab.py` | the old label kept as a synonym | the build's rename check | build stopped | yes |
| M27 | Replaced ids do not ship | `data-raw/build_vocab.py` | the id map not applied | the build's rename check | build stopped | yes |
| M28 | No quiet pass without the private inputs | `data-raw/leak_scan.py` | missing inputs treated as public-only | test_leak_scan.py | 5 checks failed | yes |
| M29 | Commit messages are scanned | `data-raw/leak_scan.py` | the message scan skipped | test_leak_scan.py | 1 check failed | yes |
| M30 | Budget-unit names count only from three words | `data-raw/leak_scan.py` | every budget-unit name counted | test_leak_scan.py | 3 checks failed | yes |
| M31 | A whole-document link is marked scheme | `inst/extdata/vocabulary.json` | one set back to `item` | test-vocab.R | 1 failure | yes |
| M32 | The reviewed allow-list is needed | the private config | one term taken off the list | `data-raw/build_vocab.py` | build stopped on `concept:pension` | yes |
| M33 | Neutral wording of three concepts | `data-raw/build_vocab.py` | the new synonym sets not applied | test-vocab.R | 3 failures | yes |

All restored: test-vocab.R and test-leak.R 0 failures, the scanner
self-test 0 failures, `git status` clean, the private config byte-identical
to its copy, and the same `grep -r "MUTANT"` search exits 1.

## Fifth run, 2026-10-30: the re-check's items

On commit `c2544c8`. The private config was copied before and compared
after; it was not changed by this run.

| Id | Safeguard | File broken | The break | Caught by | Result | Restored |
|---|---|---|---|---|---|---|
| M34 | A source id that ships renamed is a leak rule | `data-raw/leak_scan.py` | the id rules not added | test_leak_scan.py | 1 check failed | yes |
| M35 | No public file names a source id | `VOCABULARY.md` | a source id planted | the maintainer-side scan | exit 1 | yes |
| M36 | A tracked file under a private folder is caught | `data-raw/leak_scan.py` | the tracked-file check skipped | test_leak_scan.py | 1 check failed | yes |
| M37 | A private folder inside a tarball is caught | `data-raw/leak_scan.py` | the tarball check skipped | test_leak_scan.py | 1 check failed | yes |
| M38 | Removed synonyms stay removed | `data-raw/build_vocab.py` | the removal skipped | the build's check | build stopped | yes |
| M39 | Commit messages are scanned back to the root | `data-raw/leak_scan.py` | the default history cut to the last commit | test_leak_scan.py | 3 checks failed, among them the root commit's | yes |

All restored: the scanner self-test 0 failures, the maintainer-side scan 0
problems, `git status` clean, and the same `grep -r "MUTANT"` search exits 1.
