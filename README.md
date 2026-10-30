# knowledgelayer

**Short on time? Start with the review page and the decision log**
(sections 6 to 8 of the guide: `vignette("knowledge-layer", package = "knowledgelayer")`).

A reproducible analytical pipeline records how each number was made. This
package records the things the code alone cannot: which projects exist and
how they connect, who could run each one if its author were out, and how
each review decision was made. Everything is kept in plain text files beside
the code: no server, no database, and no version control needed yet.

**New in 0.2.0: a shared oversight vocabulary.** Projects, findings and
decisions can be tagged with concepts from a shared vocabulary of oversight
terms, so work described in different words ("vendor payments extract",
"contracting review") is found together. An office adds its own program
areas and agencies in a local layer. Where the vocabulary came from, and what
was removed from it, is in [VOCABULARY.md](VOCABULARY.md).

## The materials

| Material | What it's for | Where |
|---|---|---|
| This README | What the package is, install, what IT needs | Here |
| Runbook | Step-by-step walkthrough, start to finish | `kl_runbook()` in R, or [online](https://philippa-mk.github.io/knowledgelayer/) |
| Guide (vignette) | Every part worked through in R code | `vignette("knowledge-layer", package = "knowledgelayer")` |
| Example City (vignette) | The shared vocabulary, worked through with an invented city | `vignette("example-city", package = "knowledgelayer")` |
| VOCABULARY.md | Where the vocabulary came from, what was removed, its license | [VOCABULARY.md](VOCABULARY.md) |
| Sample review page | What a reviewer sees, with made-up findings, to click around in | [online](https://philippa-mk.github.io/knowledgelayer/sample-review-page.html), or beside the runbook |
| Function help | Every argument and return value | `?kl_review_page` and so on |
| Source | All of the code, readable before installing | [github.com/philippa-mk/knowledgelayer](https://github.com/philippa-mk/knowledgelayer) |

## What it does

| Part | Functions | The question it answers |
|---|---|---|
| Shared vocabulary | `kl_vocab()`, `kl_resolve()`, `kl_tag()`, `kl_vocab_extend()`, `kl_vocab_import()`, `kl_vocab_check()`, `kl_export_skos()` | Is this the same thing a colleague called by another name, and what standard does this kind of finding relate to? |
| Human review | `kl_review_angles()`, `kl_findings()`, `kl_review_page()`, `kl_read_verdicts()`, `kl_rubber_stamp_check()`, `kl_gate()` | Was each finding actually decided, by whom, and is the pipeline cleared to proceed? |
| Decision log | `kl_log_decision()`, `kl_log_head()`, `kl_verify_log()` | Who decided what, on what basis, and does the record still match what was written? |
| Project registry | `kl_init()`, `kl_add_project()`, `kl_link()`, `kl_find()` | What is this office working on, and what connects to what? |
| Single points of knowledge | `kl_single_points()`, `kl_handoff()` | Which work only one person could run, and what would a successor need? |
| Project board | `kl_inbox()`, `kl_triage()`, `kl_roadmap_status()`, `kl_board()` | What has been decided, what is parked, and what is just an idea? |
| Capability checklist | `kl_checklist()`, `kl_uk_terms()`, `kl_coverage_new()`, `kl_coverage_set()`, `kl_coverage_check()` | Measured against the UK's LG Inform Plus, what does our jurisdiction's public data infrastructure offer? |

## Install

The source is public at <https://github.com/philippa-mk/knowledgelayer>, so it
can be read in full before anything is downloaded. Three ways to install,
none needing anything beyond R:

1. **From the release file.** Download `knowledgelayer_0.2.0.tar.gz` from the
   repository's Releases page, check it against the SHA-256 checksum published
   beside it, then in R:

   ```r
   install.packages("knowledgelayer_0.2.0.tar.gz", repos = NULL, type = "source")
   ```

   Give the full path to the file if it isn't in your working directory.
2. **From r-universe,** if it has been set up for this package:

   ```r
   install.packages("knowledgelayer",
                    repos = c("https://philippa-mk.r-universe.dev", "https://cloud.r-project.org"))
   ```
3. **Straight from the repository,** if your office already allows the
   `remotes` package: `remotes::install_github("philippa-mk/knowledgelayer")`.

knowledgelayer has nothing to compile, so on R 4.2 or later Windows does not
need Rtools. **On R 4.1 under Windows**, CRAN no longer serves ready-built
packages, so `jsonlite` would arrive as source code needing Rtools40.
Install it first from CRAN's archive host, which still has the built copy:

```r
install.packages("jsonlite", repos = "https://cran-archive.r-project.org", type = "binary")
```

or install Rtools40, or upgrade R. (The package's own R 4.1 Windows test
run takes its packages from a dated January 2024 package-manager snapshot;
that affects the test run only, not what you install.)

### Packages you'll need

| Package | Needed for | If it's missing |
|---|---|---|
| R 4.1 or later | Everything | Required |
| `jsonlite` | Everything | **Required.** Not part of base R: ask IT to approve it alongside this package if it isn't already installed. |
| `openssl` | Stronger (SHA-256) fingerprints | Optional. Without it, MD5 is used. Installing it later is safe: existing records still check. |
| `targets` | Gating a pipeline on a review | Optional. Only for the pipeline examples. |
| `knitr`, `rmarkdown` | Rebuilding the guide from source | Optional. The installed guide is already built. |
| `testthat` | Running the package's own tests | Optional. |

### For IT

- **License:** MIT.
- **Dependencies:** `jsonlite` (required, not base R), plus base R's `tools`
  and `utils`. Optional: `openssl`, `targets`. See "Packages you'll need".
- **Network:** none. No function contacts the internet. The HTML review page
  and runbook are self-contained files that load nothing external and send
  nothing anywhere.
- **Compiled code:** none. Pure R. On R 4.1 under Windows, its dependency
  `jsonlite` needs either the built copy from CRAN's archive host or
  Rtools40 (see Install).
- **Files written:** only inside the folder the user points it at (creating
  subfolders there as needed).
- **Browser storage:** the review page keeps a draft of the reviewer's
  choices in the browser's local storage until it is exported or cleared
  ("Clear saved draft"). Some browsers share that storage among all local
  files, so reviewers on shared machines should clear it when done.
- **Opens a browser:** `kl_runbook()` opens the runbook in the default
  browser. Nothing else launches anything.
- **Source:** public at <https://github.com/philippa-mk/knowledgelayer>, for
  review before download.
- **Integrity:** compare the release file's SHA-256 checksum against the one
  published beside it.

## Terms used here

| Term | Meaning |
|---|---|
| Reproducible analytical pipeline (RAP) | Code that takes raw data all the way to the published output with no manual steps, so anyone can rerun it and get the same result. |
| Knowledge layer | The office's plain-file record of its projects, how they connect, who holds them, and what was decided. |
| Single point of knowledge | Work only one person could run or explain. |
| Finding | Anything a reviewer must rule on before work proceeds. |
| Verdict | The reviewer's ruling on a finding: TAKE, TWEAK, MERGE, HOLD, DISCUSS or DROP (see `kl_verdicts()`). |
| Rubber stamp | A review that approves without reviewing. |
| Hash | A short fingerprint of a file's or entry's exact contents; any change produces a different hash. |
| LG Inform Plus | A data, standards and benchmarking service run for English councils by the UK's Local Government Association. |
| esd standards | The shared lists (of services, functions, area types) behind LG Inform Plus, published under the UK's Open Government Licence. |
| Stub | A capability that has been started but does not yet work in full. |
| Controlled vocabulary | An agreed list of terms, each with one preferred name and its synonyms, so that everyone tags the same thing the same way. |
| SKOS | A web standard for publishing such vocabularies: concepts, their labels, and broader, narrower and related links. |
| Short id | A concept's identifier, such as `ft:noncompliance`. Tags store it. It never changes, and it is not a web address. |
| Crosswalk | A link from a concept to the standard it relates to, such as a GAO Green Book principle, labeled with how precise the link is. |

## Version control, when you are ready

Nothing here requires it, but everything here is ready for it. Git itself is
free, open source, and runs on your own machines; GitHub is just one
place to host it. To keep everything inside the office
network, see [Forgejo](https://forgejo.org) (GPLv3+, nonprofit-stewarded) or
[Gitea](https://about.gitea.com) (MIT, company-backed). The vignette
has more, including how to start with no server at all.

## Where the checklist comes from

The UK Local Government Association's LG Inform Plus is a shared data,
standards and benchmarking service for English councils. Its catalog of
capabilities is a ready-made checklist for any jurisdiction, and
`kl_uk_terms()` translates its UK terms. The vignette's "Fit it to your city"
section shows how to adapt it. The method was first worked through in the
author's personal DC Inform+ project.

The capability structure is drawn from LG Inform Plus public guidance; the
esd standards are reusable under the Open Government Licence with
attribution to the LG Inform Plus programme. No LGA dataset is reproduced.

## Contact

Philippa Hawker · [philippa.page](https://philippa.page) · hello@philippa.page

## License

MIT. Philippa Hawker, 2026.
