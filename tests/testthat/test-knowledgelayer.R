new_layer <- function() {
  root <- tempfile("kl-")
  kl_init(root)
  root
}

test_that("registry records projects, links and single points of knowledge", {
  root <- new_layer()
  kl_add_project("annual-2025", "Annual report 2025", owner = "Analyst A",
                 status = "done", sources = "Case management extract", path = root)
  kl_add_project("annual-2026", "Annual report 2026", owner = "Analyst A",
                 sources = c("Case management extract", "complaint intake records"), path = root)
  kl_add_project("survey", "Mentorship survey (C++ parser)", owner = "Analyst B",
                 people = c("Analyst B", "Analyst C"), path = root)
  kl_link("annual-2026", "annual-2025", "reuses-code-from", path = root)
  kl_link("annual-2026", "annual-2025", "reuses-code-from", path = root)

  expect_equal(nrow(kl_projects(root)), 3)
  expect_equal(nrow(kl_links(root)), 1)
  expect_equal(kl_find("complaint", root)$id, "annual-2026")
  expect_equal(kl_find("C++", root)$id, "survey")
  expect_error(kl_link("annual-2026", "nope", path = root), "Not registered")

  sp <- kl_single_points(path = root)
  expect_equal(sp$id, "annual-2026")
  expect_false(sp$has_handoff)

  note <- kl_handoff("annual-2026", path = root)
  expect_true(file.exists(note))
  expect_match(paste(readLines(note), collapse = "\n"), "reuses-code-from annual-2025")
  expect_true(kl_single_points(path = root)$has_handoff)

  kl_add_project("annual-2026", "Annual report 2026", owner = "Analyst A",
                 people = c("Analyst A", "Analyst D"), path = root)
  expect_equal(nrow(kl_projects(root)), 3)
  expect_equal(nrow(kl_single_points(path = root)), 0)
})

test_that("the path option replaces passing path to every call", {
  root <- new_layer()
  old <- options(knowledgelayer.path = root)
  on.exit(options(old))
  kl_add_project("p1", "Project one", owner = "A")
  expect_equal(kl_projects()$id, "p1")
  expect_equal(kl_projects(root)$id, "p1")
})

test_that("board keeps ideas off the roadmap until a person triages them", {
  root <- new_layer()
  kl_add_project("annual-2026", "Annual report 2026", owner = "Analyst A", path = root)
  a <- kl_inbox("Add district-level rates", "annual-2026", path = root)
  b <- kl_inbox("Rewrite cleaning in data.table", "annual-2026", path = root)
  c <- kl_inbox("Map of complaint density", "annual-2026", path = root)
  expect_true(all(kl_board(path = root)$list == "inbox"))

  kl_triage(c(a, b, c), c("TAKE", "HOLD", "DROP"), by = "Analyst A",
            reasons = c("", "after the report ships", "not in remit"), path = root)
  brd <- kl_board(path = root)
  expect_equal(brd$list, c("roadmap", "parking"))
  expect_equal(kl_decisions(root)$decision, "DROP")
  expect_error(kl_triage(a, "HOLD", by = "A", path = root), "already on the roadmap")

  expect_error(kl_roadmap_status(a, "done", path = root), "how you know it works")
  kl_roadmap_status(a, "done", checked = "matches WP-7 totals", path = root)
  for (k in 1:2) kl_triage(b, "HOLD", by = "Analyst A", path = root)
  expect_true(kl_board(path = root)$stale[kl_board(path = root)$id == b])

  note <- paste(readLines(kl_handoff("annual-2026", path = root)), collapse = "\n")
  expect_match(note, "Decisions and why", fixed = TRUE)
  expect_match(note, "[roadmap: done] Add district-level rates", fixed = TRUE)
  expect_match(note, "(parked 3+ triages)", fixed = TRUE)
})

test_that("a triage with a bad id changes nothing", {
  root <- new_layer()
  a <- kl_inbox("Idea", "p", path = root)
  expect_error(kl_triage(c(a, "i999"), c("DROP", "TAKE"), by = "A", path = root), "i999")
  expect_equal(kl_board(path = root)$list, "inbox")
  expect_equal(nrow(kl_decisions(root)), 0)
})

test_that("checklist ships with attribution, no ratings, and a terms table", {
  cl <- kl_checklist()
  expect_equal(nrow(cl), 37)
  expect_false(any(grepl("status", setdiff(names(cl), "uk_status"))))
  expect_equal(leak_hits(unlist(cl)), character())
  terms <- kl_uk_terms()
  expect_true(all(c("GSS code", "LSOA / MSOA", "RoPA (record of processing activities)") %in% terms$term))
  expect_false(anyNA(terms$us_nearest))
  expect_true(all(cl$uk_status %in% c("confirmed-live", "documented-from-guides")))
  expect_match(attr(cl, "attribution"), "Open Government Licence")
})

test_that("coverage matrix separates unassessed from missing and demands evidence", {
  m <- kl_coverage_new("Example City")
  expect_true(all(is.na(m$local_status)))
  expect_equal(nrow(kl_coverage_check(m)), 0)

  m <- kl_coverage_set(m, "cap-api-open-data", "City data portal", "stub",
                       gap = "API exists; no standards spine")
  chk <- kl_coverage_check(m)
  expect_equal(chk$level, "error")
  expect_match(chk$problem, "no evidence")

  m <- kl_coverage_set(m, "cap-api-open-data", "City data portal", "stub",
                       evidence = "Portal API documentation", gap = "API exists; no standards spine")
  m <- kl_coverage_set(m, "pat-12-versioned-changelog", status = "missing")
  chk <- kl_coverage_check(m)
  expect_equal(chk$level, "warning")

  m$checked[m$id == "cap-api-open-data"] <- NA
  chk <- kl_coverage_check(m)
  expect_true(any(chk$level == "error" & grepl("no checked date", chk$problem)))

  s <- kl_coverage_summary(m)
  expect_equal(sum(s[, "unassessed"]), 35)
  expect_equal(attr(m, "jurisdiction"), "Example City")
})

test_that("decision log is a hash chain that detects tampering", {
  root <- new_layer()
  kl_log_decision("Exclude test records", "approved", by = "Analyst A",
                  assurance = "self-reviewed", path = root)
  kl_log_decision("Use 2024 boundaries", "approved", by = "Analyst A",
                  assurance = "peer-reviewed", reviewed_by = "Analyst B",
                  evidence = c("wp-12.xlsx", "memo.docx"), path = root)
  kl_log_decision("Drop chart 4", "DROP", by = "Analyst B", path = root)
  expect_equal(nrow(kl_decisions(root)), 3)
  expect_true(suppressMessages(kl_verify_log(root)))

  expect_error(kl_log_decision("x", "y", by = "A", assurance = "independent", path = root),
               "needs a reviewer")
  expect_error(kl_log_decision("x", "y", by = "A", assurance = "peer-reviewed",
                               reviewed_by = " a ", path = root), "needs a reviewer")

  log <- file.path(root, "knowledge", "decisions.jsonl")
  lines <- readLines(log)
  edited <- lines
  edited[2] <- sub("Use 2024 boundaries", "Use 2023 boundaries", edited[2])
  writeLines(edited, log)
  expect_error(kl_verify_log(root), "Entry 2 was changed")

  writeLines(lines[-2], log)
  expect_error(kl_verify_log(root), "Entry 2 does not follow")
})

test_that("a recorded head catches what the chain alone cannot", {
  root <- new_layer()
  for (w in c("one", "two", "three")) kl_log_decision(w, "ok", by = "A", path = root)
  head <- suppressMessages(kl_log_head(root))
  expect_match(head, "^3:")
  kl_log_decision("four", "ok", by = "A", path = root)
  expect_true(suppressMessages(kl_verify_log(root, expect_head = head)))

  log <- file.path(root, "knowledge", "decisions.jsonl")
  writeLines(readLines(log)[1:2], log)
  expect_true(suppressMessages(kl_verify_log(root)))
  expect_error(kl_verify_log(root, expect_head = head), "removed")

  unlink(log)
  file.create(log)
  for (w in c("one", "FORGED", "three")) kl_log_decision(w, "ok", by = "A", path = root)
  expect_true(suppressMessages(kl_verify_log(root)))
  expect_error(kl_verify_log(root, expect_head = head), "rewritten")
})

test_that("non-English text survives the log and registry unchanged", {
  root <- new_layer()
  who <- "Łukasz Nguyễn"
  kl_log_decision("Exclude café records", "approved", by = who, path = root)
  kl_add_project("pé", "Résumé review", owner = who, path = root)
  expect_true(suppressMessages(kl_verify_log(root)))
  expect_equal(kl_decisions(root)$by, who)
  expect_equal(kl_projects(root)$owner, who)
})

fake_export <- function(findings, verdicts, notes = "", reviewer = "Reviewer R",
                        author = "Analyst A", seen = 30, touched = FALSE,
                        opened = "2026-10-29T15:00:00Z", exported = "2026-10-29T15:20:00Z",
                        hash = knowledgelayer:::findings_hash(findings), ids = findings$id) {
  notes <- rep_len(notes, nrow(findings))
  items <- lapply(seq_len(nrow(findings)), function(i) list(
    verdict = verdicts[i], proposed = findings$proposed_verdict[i],
    severity = findings$severity[i], target = "", finding = findings$finding[i],
    proposedFix = findings$proposed_fix[i], note = notes[i],
    touched = touched, seenSeconds = seen))
  names(items) <- findings$id
  items <- items[ids]
  file <- tempfile("APPROVED_", fileext = ".json")
  jsonlite::write_json(list(schema = "approved-set/1.0", loop = "review", review = "qa-test",
                            author = author, reviewer = reviewer,
                            generatedAt = "2026-10-29T14:00:00Z", openedAt = opened,
                            exportedAt = exported, findingsHash = hash, items = items,
                            notes = list(`__page` = "")),
                       file, auto_unbox = TRUE)
  file
}

findings5 <- function() {
  kl_findings(id = paste0("F", 1:5),
              finding = c("Duplicate records after join", "Label off by a year",
                          "Rate uses wrong denominator", "Footnote missing", "Typo"),
              severity = c("high", "low", "high", "med", "low"),
              proposed_fix = c("Dedupe on record id", "Fix label", "Use population",
                               "Add footnote", "Fix typo"))
}

test_that("review page is self-contained and survives hostile finding text", {
  f <- kl_findings(c("F1", "F2"),
                   c("Text with </script> and \\backslash\\ and \"quotes\"",
                     "Compare counts <!--<script> in the raw log"),
                   c("high", "low"), c("Fix it", "Fix that"))
  page <- tempfile(fileext = ".html")
  kl_review_page(f, page, "qa-test", title = "QA <test>", author = "Analyst A",
                 return_to = "Analyst A")
  html <- paste(readLines(page, encoding = "UTF-8"), collapse = "\n")
  expect_false(grepl("__KL_DATA__", html, fixed = TRUE))
  data <- sub("(?s).*const KL = (.*?);\n\\(function.*", "\\1", html, perl = TRUE)
  expect_false(grepl("<", data, fixed = TRUE))
  expect_match(html, "<title>QA &lt;test&gt;</title>", fixed = TRUE)
  expect_match(html, "\\\\backslash\\\\", fixed = TRUE)
  expect_equal(jsonlite::fromJSON(data)$findings$finding[2],
               "Compare counts <!--<script> in the raw log")
  expect_error(kl_findings("F1", "x", "urgent", "y"), "Unknown severity")
  expect_error(kl_findings("F1", "x", "low", "y", proposed_verdict = "TWEAK"),
               "belongs to the reviewer")
  expect_equal(nrow(kl_review_angles()), 7)
})

test_that("findings survive a CSV round trip without looking tampered with", {
  f <- findings5()
  csv <- tempfile(fileext = ".csv")
  kl_write_findings(f, csv)
  back <- kl_read_findings(csv)
  expect_identical(knowledgelayer:::findings_hash(back), knowledgelayer:::findings_hash(f))
  plain <- utils::read.csv(csv)
  expect_true(is.logical(plain$target))
  expect_identical(knowledgelayer:::findings_hash(plain), knowledgelayer:::findings_hash(f))
  v <- kl_read_verdicts(fake_export(f, c("TAKE", "TAKE", "TAKE", "HOLD", "DROP"), notes = "ok"))
  expect_false(any(kl_rubber_stamp_check(v, back)$level == "error"))
})

test_that("rubber-stamp check passes a real review and flags a sign-off", {
  f <- findings5()
  ok <- kl_read_verdicts(fake_export(f, c("TAKE", "TWEAK", "TAKE", "HOLD", "DROP"),
                                     notes = c("Checked against WP-3", "Use FY not CY",
                                               "Agreed", "", "")))
  chk <- kl_rubber_stamp_check(ok, f)
  expect_equal(nrow(chk), 0)

  stamp <- kl_read_verdicts(fake_export(f, rep("TAKE", 5), seen = 1,
                                        exported = "2026-10-29T15:00:08Z"))
  chk <- kl_rubber_stamp_check(stamp, f)
  expect_true(any(grepl("every proposal accepted", chk$flag)))
  expect_true(any(grepl("decided in 8 seconds", chk$flag)))
  expect_true(any(grepl("never touched", chk$flag)))
  expect_true(any(chk$id == "F1" & grepl("high-severity finding decided without a note", chk$flag)))
  expect_output(print(chk), "PASS WITH WARNINGS")

  bad <- kl_read_verdicts(fake_export(f, c("TWEAK", rep("TAKE", 4)), reviewer = "analyst a "))
  chk <- kl_rubber_stamp_check(bad, f)
  expect_true(any(chk$level == "error" & grepl("TWEAK with no note", chk$flag)))
  expect_true(any(grepl("self-reviewed", chk$flag)))

  anon <- kl_read_verdicts(fake_export(f, f$proposed_verdict, notes = "ok", reviewer = ""))
  expect_true(any(kl_rubber_stamp_check(anon, f)$flag == "no reviewer named"))

  changed <- f
  changed$finding[1] <- "Edited after review"
  chk <- kl_rubber_stamp_check(kl_read_verdicts(fake_export(f, f$proposed_verdict,
                                                            notes = "ok")), changed)
  expect_true(any(grepl("differ from the ones reviewed", chk$flag)))
})

test_that("an export missing findings cannot pass the gate", {
  f <- findings5()
  partial <- fake_export(f, f$proposed_verdict, notes = "ok", ids = c("F2", "F4"))
  chk <- kl_rubber_stamp_check(kl_read_verdicts(partial), f)
  expect_true(any(chk$level == "error" & grepl("no decision recorded", chk$flag)))
  expect_error(capture.output(kl_gate(partial, f)), "nothing proceeds")
})

test_that("gate returns only cleared findings and refuses a failed review", {
  f <- findings5()
  root <- new_layer()
  file <- fake_export(f, c("TAKE", "TWEAK", "DROP", "HOLD", "TAKE"),
                      notes = c("ok", "Use FY not CY", "", "", ""))
  cleared <- kl_gate(file, f, log = TRUE, path = root)
  expect_setequal(cleared$id, c("F1", "F2", "F5"))
  expect_equal(cleared$instruction[cleared$id == "F2"], "Use FY not CY")
  expect_equal(cleared$instruction[cleared$id == "F1"], "Dedupe on record id")
  expect_equal(kl_gate(file)$instruction[1], "Dedupe on record id")

  d <- kl_decisions(root)
  expect_equal(d$assurance, "peer-reviewed")
  expect_equal(d$by, "Analyst A")
  expect_true(suppressMessages(kl_verify_log(root)))

  bad <- fake_export(f, c("MERGE", rep("TAKE", 4)))
  expect_error(capture.output(kl_gate(bad, f)), "nothing proceeds")

  empty <- tempfile(fileext = ".json")
  writeLines('{"schema":"approved-set/1.0","items":{}}', empty)
  expect_error(kl_gate(empty), "records no decisions")
})

test_that("newest verdict file is found", {
  d <- tempfile("exports-")
  dir.create(d)
  writeLines("{}", file.path(d, "APPROVED_qa_2026-10-01.json"))
  Sys.setFileTime(file.path(d, "APPROVED_qa_2026-10-01.json"), Sys.time() - 3600)
  writeLines("{}", file.path(d, "APPROVED_qa_2026-10-02.json"))
  expect_equal(basename(kl_newest_verdicts(d)), "APPROVED_qa_2026-10-02.json")
  expect_error(kl_newest_verdicts(d, review = "other"), "No APPROVED")
})

test_that("a review stays valid when the hash method changes after the page was made", {
  f <- findings5()
  md5 <- knowledgelayer:::findings_hash(f, algo = "md5")
  v <- kl_read_verdicts(fake_export(f, c("TAKE", "TAKE", "TAKE", "HOLD", "DROP"),
                                    notes = "ok", hash = md5))
  expect_false(any(kl_rubber_stamp_check(v, f)$level == "error"))
  changed <- f
  changed$finding[1] <- "Edited after review"
  expect_true(any(grepl("differ from the ones reviewed",
                        kl_rubber_stamp_check(v, changed)$flag)))
})

test_that("writing findings and pages creates the folders they need", {
  d <- file.path(tempfile("fresh-"), "qa", "nested")
  f <- findings5()
  kl_write_findings(f, file.path(d, "findings.csv"))
  kl_review_page(f, file.path(d, "REVIEW.html"), "qa-test")
  expect_true(file.exists(file.path(d, "findings.csv")))
  expect_true(file.exists(file.path(d, "REVIEW.html")))
})

test_that("a minimal hand-written export reads, and a missing verdict is named", {
  ok <- tempfile(fileext = ".json")
  writeLines('{"schema":"approved-set/1.0","reviewer":"R","items":{"F1":{"verdict":"TAKE"}}}', ok)
  v <- kl_read_verdicts(ok)
  expect_equal(v$proposed, "")
  bad <- tempfile(fileext = ".json")
  writeLines('{"schema":"approved-set/1.0","items":{"F1":{"note":"x"}}}', bad)
  expect_error(kl_read_verdicts(bad), "'F1' has no verdict")
})

test_that("the license attribution survives a checklist with added rows", {
  mine <- data.frame(id = "cap-local", kind = "capability", theme = "data-and-reports",
                     capability = "A local source", uk_tool = "", uk_status = "")
  city <- kl_coverage_new("Example City", checklist = rbind(kl_checklist(), mine))
  expect_match(attr(city, "attribution"), "Open Government Licence")
  expect_equal(nrow(city), 38)
})

test_that("the review page discloses what it records and offers to clear its draft", {
  page <- tempfile(fileext = ".html")
  kl_review_page(findings5(), page, "qa-test")
  html <- paste(readLines(page, encoding = "UTF-8"), collapse = "\n")
  expect_match(html, "when you opened the page and when you exported", fixed = TRUE)
  expect_match(html, "Clear saved draft", fixed = TRUE)
  expect_match(html, "store.clear()", fixed = TRUE)
})

test_that("public examples carry no local references", {
  pkg <- system.file(package = "knowledgelayer")
  files <- c(list.files(file.path(pkg, "runbook"), full.names = TRUE),
             list.files(file.path(pkg, "doc"), pattern = "\\.(Rmd|R|html)$", full.names = TRUE))
  txt <- paste(unlist(lapply(files, readLines, warn = FALSE)), collapse = "\n")
  expect_equal(leak_hits(txt), character())
})
