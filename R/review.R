#' The review verdicts
#'
#' Six verdicts, each with a defined consequence, so that what a reviewer
#' meant survives into the next pass without anyone interpreting it.
#'
#' @return A named character vector: verdict to meaning.
#' @export
kl_verdicts <- function() {
  c(
    TAKE = "Accept the finding and apply the proposed fix as written.",
    TWEAK = "Accept the finding; the reviewer's note replaces the proposed fix.",
    MERGE = "Same underlying issue as another finding; the note names which.",
    HOLD = "Real, but not this pass. Returns next review.",
    DISCUSS = "Undecided; talk it through before anyone acts.",
    DROP = "Not a finding, or will not fix. Logged only."
  )
}

finding_cols <- c("id", "finding", "severity", "proposed_fix",
                  "proposed_verdict", "source", "target", "typology")

#' Build a set of findings for review
#'
#' Findings are anything a person must rule on before work proceeds: data
#' quality exceptions, independent-review comments, open methodological
#' choices. Every finding carries a proposed verdict so the reviewer's
#' fastest path is confirming a considered proposal, not drafting one, and
#' every departure from a proposal is visible afterwards.
#'
#' @param id Short ids, e.g. `"F1"`.
#' @param finding What was found, with its evidence.
#' @param severity `"high"` (blocks publication or would be caught by a
#'   reader at once), `"med"` (weakens the work), or `"low"` (polish).
#' @param proposed_fix What should be done about it.
#' @param proposed_verdict One of [kl_verdicts()] names except `"TWEAK"`.
#'   Defaults to `"TAKE"`. Propose the verdict you would actually stand
#'   behind, and `"DISCUSS"` if you cannot. `"TWEAK"` is the reviewer's
#'   alone: it means "yes, but my way", and only the reviewer's note can say
#'   what that way is.
#' @param source Where it came from: a check, a reviewer, a script.
#' @param target Optional id of the project or task it turns into.
#' @param typology Optional kind of finding, from the findings typology
#'   (`kl_vocab("findings_typology")`): an id such as `"ft:noncompliance"` or
#'   a label such as `"segregation of duties"`. Resolved with [kl_resolve()]
#'   and stored as the short id; anything that does not resolve to exactly
#'   one kind is refused. The review page shows each finding's kind and its
#'   crosswalks to the standards.
#' @param path Folder holding the layer, for an office's own kinds of
#'   finding added with [kl_vocab_extend()].
#' @return A data frame of findings, every column character.
#' @examples
#' f <- kl_findings(
#'   id = c("F1", "F2"),
#'   finding = c("312 records appear twice after the address join",
#'               "Chart 3 labels the 2025 series as 2024"),
#'   severity = c("high", "low"),
#'   proposed_fix = c("Deduplicate on record id before the join",
#'                    "Fix the label in the plot function"))
#' @export
kl_findings <- function(id, finding, severity, proposed_fix,
                        proposed_verdict = "TAKE", source = "", target = "",
                        typology = "", path = kl_path()) {
  f <- canon_findings(data.frame(
    id = id, finding = finding, severity = severity, proposed_fix = proposed_fix,
    proposed_verdict = proposed_verdict, source = source, target = target,
    typology = typology))
  typed <- nzchar(trimws(f$typology))
  for (i in which(typed)) {
    f$typology[i] <- resolve_or_stop(f$typology[i], scheme = context_scheme("finding"), path = path)
  }
  bad_sev <- setdiff(f$severity, c("high", "med", "low"))
  if (length(bad_sev)) stop("Unknown severity: ", paste(bad_sev, collapse = ", "), call. = FALSE)
  bad_v <- setdiff(f$proposed_verdict, names(kl_verdicts()))
  if (length(bad_v)) stop("Unknown verdict: ", paste(bad_v, collapse = ", "), call. = FALSE)
  if (any(f$proposed_verdict == "TWEAK")) {
    stop("TWEAK cannot be proposed: it belongs to the reviewer, whose note is the fix. ",
         "Propose TAKE with your fix, or DISCUSS.", call. = FALSE)
  }
  if (anyDuplicated(f$id)) stop("Finding ids must be unique.", call. = FALSE)
  f
}

# One shape for findings wherever they come from (built here, read from CSV,
# edited by hand), so a round trip through a file never changes the hash.
canon_findings <- function(f) {
  for (k in setdiff(finding_cols, names(f))) f[[k]] <- ""
  f <- f[, finding_cols, drop = FALSE]
  f[] <- lapply(f, function(x) {
    x <- as.character(x)
    x[is.na(x)] <- ""
    x
  })
  f <- f[order(f$id), , drop = FALSE]
  rownames(f) <- NULL
  f
}

# A v0.1 set of findings has no typology column. Leaving an all-empty one
# out keeps its fingerprint unchanged, so a review exported under v0.1 still
# matches its findings after the upgrade.
findings_hash <- function(findings, algo = NULL) {
  f <- canon_findings(findings)
  if (!any(nzchar(f$typology))) f$typology <- NULL
  kl_hash(as.character(jsonlite::toJSON(f, dataframe = "rows")), algo = algo)
}

# Missing folders are created, so a fresh "qa/" path works first time.
ensure_dir <- function(file) {
  dir.create(dirname(file), recursive = TRUE, showWarnings = FALSE)
  file
}

#' Save and load findings
#'
#' Keep findings in a CSV file beside the pipeline, edited in a spreadsheet
#' if that is easier, and read them back without changing them. Every
#' column is read as text, so an empty column does not quietly become `NA`
#' and make the review look tampered with.
#'
#' @param findings From [kl_findings()].
#' @param file Path to the CSV file. Missing folders are created.
#' @param path Folder holding the layer, used to resolve a typology the
#'   office added itself.
#' @return `kl_write_findings()` returns the path invisibly;
#'   `kl_read_findings()` returns the findings, validated.
#' @export
kl_write_findings <- function(findings, file) {
  utils::write.csv(canon_findings(findings), ensure_dir(file), row.names = FALSE,
                   fileEncoding = "UTF-8")
  invisible(file)
}

#' @rdname kl_write_findings
#' @export
kl_read_findings <- function(file, path = kl_path()) {
  f <- utils::read.csv(file, colClasses = "character", na.strings = character(),
                       fileEncoding = "UTF-8")
  do.call(kl_findings, c(as.list(canon_findings(f)[, finding_cols]), path = path))
}

#' Angles for a hard, fair review
#'
#' A checklist for whoever reviews a report before it goes out, used to
#' generate findings for [kl_findings()]. The reviewer plays the reader who
#' wants the work to be wrong, and works from the actual text and numbers,
#' never from memory or a summary. It complements a standard independent
#' review template: that checks the report matches the work papers; this
#' checks how the report will be read.
#'
#' Say what works as well as what does not. A review that finds only
#' problems, or only praise, has not looked hard enough, and an honest
#' severity scale keeps "high" meaningful.
#'
#' @return A data frame of angles with the question each one asks.
#' @export
kl_review_angles <- function() {
  data.frame(
    angle = c("Claims vs evidence", "The numbers", "Read it closely", "A hostile reader",
              "Out of context", "Privacy and promises", "What could go wrong"),
    question = c(
      "Does any headline, finding or 'only', 'first' or 'all' go further than the evidence shows? Do two sections disagree?",
      "Do totals add up? Does each figure match everywhere it appears: text, tables, charts, summary? Is 'unknown' shown as zero?",
      "Read several sections word for word, not the summary. This is where mistakes hide.",
      "What would someone who wants to dismiss this report seize on first?",
      "Could any single sentence, number or chart label be quoted out of context and used against the office?",
      "Does it reveal anything about a person it should not? Does it commit the office to anything it cannot deliver?",
      "On publication day, what happens if a figure is challenged, a link breaks, or the agency disputes a finding?"
    )
  )
}

#' Write an interactive review page
#'
#' Produces one self-contained HTML file, with no server and no internet
#' needed, that a reviewer opens in any browser. Each finding gets the six
#' verdicts with the proposal preselected, and a note field. Export saves
#' `APPROVED_<review>_<date>.json`: the record of what was proposed, what was
#' decided, by whom and when. Read it back with [kl_read_verdicts()].
#'
#' The page tells the reviewer what it records: the decisions, the notes,
#' and how long each finding was on screen and whether it was touched.
#' [kl_rubber_stamp_check()] uses the last two to tell a review from a
#' sign-off. Work in progress is saved in the reviewer's browser, so closing
#' the tab does not lose it.
#'
#' @param findings From [kl_findings()].
#' @param file Where to write the page.
#' @param review_id Identifier for this review, e.g. `"annual-report-qa-2026"`.
#' @param title Heading shown on the page.
#' @param author Who prepared the findings. Recorded so self-review shows.
#' @param intro Optional paragraph explaining the review to the reviewer.
#' @param return_to Who the reviewer sends the exported file to, e.g.
#'   `"Analyst A (analyst.a@example.org)"`. Shown on the page.
#' @param path Folder holding the layer, for an office's own kinds of
#'   finding.
#' @details A finding with a `typology` shows its kind and its crosswalks to
#'   the standards (GAO Green Book, COSO, NIST and others), each labeled with
#'   how precise the link is. Only a link to the exact item, principle or
#'   section is offered as a link to that point; a link to a whole standard
#'   or to a search page says so.
#' @return The file path, invisibly.
#' @export
kl_review_page <- function(findings, file, review_id, title = review_id,
                           author = "", intro = "", return_to = "", path = kl_path()) {
  stopifnot(is.data.frame(findings), nrow(findings) > 0)
  findings <- canon_findings(findings)
  types <- unique(findings$typology[nzchar(findings$typology)])
  v <- kl_vocab(path = path)
  vocab <- lapply(types, function(t) list(
    label = v$prefLabel[match(t, v$id)] %|na|% t,
    mappings = kl_crosswalks(t, path = path)[, c("scheme", "label", "uri", "precision_label")]))
  names(vocab) <- types
  data <- list(
    review = review_id, title = title, author = author, intro = intro,
    returnTo = return_to, generatedAt = now_utc(),
    findingsHash = findings_hash(findings),
    verdicts = as.list(kl_verdicts()),
    findings = findings,
    vocab = if (length(vocab)) vocab else structure(list(), names = character())
  )
  json <- as.character(jsonlite::toJSON(data, auto_unbox = TRUE, dataframe = "rows"))
  # Every "<" is escaped, not only "</": a finding quoting "<!--<script>"
  # would otherwise end the script block early and blank the page.
  json <- replace_literal(json, "<", "\\u003c")
  tpl <- readLines(system.file("review", "review-page.html", package = "knowledgelayer"),
                   warn = FALSE, encoding = "UTF-8")
  tpl <- paste(tpl, collapse = "\n")
  page <- replace_literal(tpl, "/*__KL_DATA__*/null", json)
  page <- replace_literal(page, "__KL_TITLE__", html_escape(title))
  write_utf8(c(page, ""), ensure_dir(file))
  invisible(file)
}

# sub() treats backslashes in the replacement as escapes even with
# fixed = TRUE, which would corrupt escaped JSON; split and rejoin instead.
replace_literal <- function(x, pattern, replacement) {
  pos <- gregexpr(pattern, x, fixed = TRUE)[[1]]
  if (pos[1] == -1) return(x)
  starts <- c(1, pos + nchar(pattern))
  ends <- c(pos - 1, nchar(x))
  paste(substring(x, starts, ends), collapse = replacement)
}

html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

#' Read an exported verdict file
#'
#' @param file Path to an `APPROVED_*.json` export.
#' @return A data frame, one row per finding, carrying the finding text and
#'   proposed fix as reviewed, with the review's metadata (reviewer, author,
#'   timestamps, findings hash) as attributes.
#' @export
kl_read_verdicts <- function(file) {
  x <- jsonlite::read_json(file, simplifyVector = FALSE)
  if (!identical(x$schema, "approved-set/1.0")) {
    stop("Not a verdict export: ", file, call. = FALSE)
  }
  if (!length(x$items)) {
    stop("This export records no decisions, so there is nothing to act on: ", file,
         call. = FALSE)
  }
  rows <- lapply(names(x$items), function(id) {
    it <- x$items[[id]]
    if (is.null(it$verdict) || !nzchar(it$verdict)) {
      stop("Finding '", id, "' has no verdict in ", basename(file), ".", call. = FALSE)
    }
    data.frame(id = id, verdict = it$verdict, proposed = it$proposed %||% "",
               severity = it$severity %||% "", note = it$note %||% "",
               finding = it$finding %||% "", proposed_fix = it$proposedFix %||% "",
               target = it$target %||% "", touched = isTRUE(it$touched),
               seen_seconds = as.numeric(it$seenSeconds %||% 0))
  })
  v <- do.call(rbind, rows)
  for (k in c("review", "reviewer", "author", "generatedAt", "openedAt",
              "exportedAt", "findingsHash")) {
    attr(v, k) <- x[[k]] %||% ""
  }
  attr(v, "page_note") <- x$notes$`__page` %||% ""
  attr(v, "file") <- normalizePath(file)
  class(v) <- c("kl_verdicts", class(v))
  v
}

#' Find the newest verdict export
#'
#' @param dir Folder the reviewer's exports are saved to.
#' @param review Optional review id to match.
#' @return Path to the most recently modified `APPROVED_*.json`, or an
#'   error if there is none.
#' @export
kl_newest_verdicts <- function(dir = ".", review = NULL) {
  f <- list.files(dir, pattern = "^APPROVED_.*\\.json$", full.names = TRUE)
  if (!is.null(review)) f <- f[grepl(review, basename(f), fixed = TRUE)]
  if (!length(f)) stop("No APPROVED_*.json export in '", dir, "'.", call. = FALSE)
  f[which.max(file.mtime(f))]
}

#' Tell a review from a rubber stamp
#'
#' Checks an exported verdict file for the marks of a review that did not
#' happen: every proposal accepted with no notes, findings never on screen
#' long enough to read, high-severity findings waved through without
#' comment, a reviewer reviewing their own work. It also enforces the
#' verdicts' own rules: a `TWEAK` or `MERGE` without a note cannot be acted
#' on. Given the findings, it confirms every finding has a decision and
#' that the findings are the ones that were reviewed.
#'
#' Nothing here proves a review was careful, and the export is an ordinary
#' file a determined person could edit. It catches the reviews that plainly
#' were not careful, and makes the rest explainable.
#'
#' @param verdicts From [kl_read_verdicts()].
#' @param findings Optionally, the findings the page was built from.
#' @param min_seconds Seconds a finding should be on screen to count as read.
#' @return A data frame of flags (`id`, `level`, `flag`) with class
#'   `kl_stamp_check`. Its print method gives an overall result: `PASS`,
#'   `PASS WITH WARNINGS` or `FAIL`.
#' @export
kl_rubber_stamp_check <- function(verdicts, findings = NULL, min_seconds = 5) {
  out <- list()
  add <- function(id, level, flag) {
    out[[length(out) + 1]] <<- data.frame(id = id, level = level, flag = flag)
  }
  v <- verdicts
  n <- nrow(v)
  same_person <- function(a, b) tolower(trimws(a)) == tolower(trimws(b))
  reviewer <- trimws(attr(v, "reviewer"))
  author <- trimws(attr(v, "author"))
  if (!nzchar(reviewer)) add("(review)", "error", "no reviewer named")
  if (nzchar(reviewer) && nzchar(author) && same_person(reviewer, author)) {
    add("(review)", "warning", "reviewer is the author: record this as self-reviewed")
  }
  if (!is.null(findings)) {
    missing <- setdiff(findings$id, v$id)
    if (length(missing)) {
      add(paste(missing, collapse = ", "), "error", "no decision recorded for these findings")
    }
    extra <- setdiff(v$id, findings$id)
    if (length(extra)) {
      add(paste(extra, collapse = ", "), "warning", "decisions on findings not in this set")
    }
    recorded <- attr(v, "findingsHash")
    # Compare with the method the page used, not today's default: the default
    # changes when 'openssl' is installed, which must not look like tampering.
    algo <- if (grepl("^(sha256|md5):", recorded)) sub(":.*$", "", recorded) else NULL
    now <- tryCatch(findings_hash(findings, algo = algo), error = function(e) NULL)
    if (is.null(now)) {
      add("(review)", "error", paste0(
        "cannot confirm the findings are the ones reviewed: the page recorded a ", algo,
        " fingerprint, which needs the 'openssl' package here"))
    } else if (!length(missing) && !identical(now, recorded)) {
      add("(review)", "error",
          "these findings differ from the ones reviewed: wording, severity or proposal changed since")
    }
  }
  for (i in seq_len(n)) {
    has_note <- nzchar(trimws(v$note[i]))
    if (v$verdict[i] %in% c("TWEAK", "MERGE") && !has_note) {
      add(v$id[i], "error", paste(v$verdict[i], "with no note: nothing to act on"))
    }
    if (v$severity[i] == "high" && !has_note) {
      add(v$id[i], "warning", "high-severity finding decided without a note")
    }
    if (v$seen_seconds[i] < min_seconds && !v$touched[i]) {
      add(v$id[i], "warning", sprintf("on screen %.0fs and never touched", v$seen_seconds[i]))
    }
  }
  if (n >= 5 && all(v$verdict == v$proposed) && !any(nzchar(trimws(v$note))) &&
      !nzchar(trimws(attr(v, "page_note")))) {
    add("(review)", "warning",
        "every proposal accepted unchanged with no notes: confirm this was a review, not a sign-off")
  }
  opened <- as.POSIXct(attr(v, "openedAt"), format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
  exported <- as.POSIXct(attr(v, "exportedAt"), format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
  if (!is.na(opened) && !is.na(exported)) {
    secs <- as.numeric(difftime(exported, opened, units = "secs"))
    if (secs < n * min_seconds) {
      add("(review)", "warning", sprintf("%d findings decided in %.0f seconds", n, secs))
    }
  }
  res <- if (length(out)) do.call(rbind, out) else
    data.frame(id = character(), level = character(), flag = character())
  structure(res, class = c("kl_stamp_check", "data.frame"))
}

#' @export
print.kl_stamp_check <- function(x, ...) {
  result <- if (any(x$level == "error")) "FAIL" else
    if (nrow(x)) "PASS WITH WARNINGS" else "PASS"
  cat("Review check:", result, "\n")
  if (nrow(x)) {
    df <- x
    class(df) <- "data.frame"
    print(df, row.names = FALSE)
  }
  invisible(x)
}

#' Gate a pipeline step on a human review
#'
#' The export is the only thing that authorizes the next pass. `kl_gate()`
#' reads it, refuses to continue if the review check finds an error, and
#' returns just the findings cleared to act on, with the reviewer's note as
#' the instruction for any `TWEAK`. Use it as a target in a 'targets'
#' pipeline so the report cannot build until the review is in.
#'
#' In a pipeline, leave `log = FALSE` and record the review once with
#' [kl_log_verdicts()]: a target can rerun many times, and each run with
#' `log = TRUE` would add another log entry.
#'
#' @param file Path to an `APPROVED_*.json` export.
#' @param findings Optionally, the findings the page was built from. Supply
#'   them: it is how a missing or altered finding is caught.
#' @param act_on Verdicts that clear a finding for action.
#' @param log If `TRUE`, also record the review in the decision log at
#'   `path`.
#' @param path Folder holding the layer, used when `log = TRUE`.
#' @return The findings cleared for action, as a data frame.
#' @export
kl_gate <- function(file, findings = NULL, act_on = c("TAKE", "TWEAK"),
                    log = FALSE, path = kl_path()) {
  v <- kl_read_verdicts(file)
  chk <- kl_rubber_stamp_check(v, findings)
  if (any(chk$level == "error")) {
    print(chk)
    stop("Review did not pass; nothing proceeds.", call. = FALSE)
  }
  if (log) kl_log_verdicts(v, path = path)
  out <- v[v$verdict %in% act_on, , drop = FALSE]
  out$instruction <- ifelse(out$verdict == "TWEAK", out$note, out$proposed_fix)
  class(out) <- "data.frame"
  rownames(out) <- NULL
  out[, c("id", "verdict", "severity", "finding", "instruction", "note", "target")]
}

#' Record a completed review in the decision log
#'
#' One log entry for the whole review, pointing at the export by its hash,
#' so the decision log proves which verdict file was relied on.
#'
#' @param verdicts From [kl_read_verdicts()].
#' @param path Folder holding the layer.
#' @return The new entry's hash, invisibly.
#' @export
kl_log_verdicts <- function(verdicts, path = kl_path()) {
  reviewer <- trimws(attr(verdicts, "reviewer"))
  author <- trimws(attr(verdicts, "author"))
  independent <- nzchar(author) && tolower(author) != tolower(reviewer)
  tally <- table(verdicts$verdict)
  kl_log_decision(
    what = paste("Review", attr(verdicts, "review")),
    decision = paste(names(tally), tally, sep = " ", collapse = ", "),
    by = if (nzchar(author)) author else reviewer,
    basis = paste(nrow(verdicts), "findings reviewed by", reviewer),
    evidence = c(basename(attr(verdicts, "file")), kl_hash(attr(verdicts, "file"), file = TRUE)),
    assurance = if (independent) "peer-reviewed" else "self-reviewed",
    reviewed_by = if (independent) reviewer else "",
    ref = attr(verdicts, "review"), path = path
  )
}
