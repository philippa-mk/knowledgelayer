assurance_levels <- c("self-reviewed", "peer-reviewed", "independent")

#' Record a decision in the log
#'
#' Appends one line to `knowledge/decisions.jsonl`. Each entry carries the
#' hash of the entry before it, so the log is a chain: editing, removing or
#' reordering any earlier entry breaks the chain, and [kl_verify_log()]
#' says where.
#'
#' What the chain cannot catch on its own is someone rewriting the whole
#' file, or quietly removing the newest entries. For that, record the head
#' somewhere outside the folder from time to time, for instance in the work
#' papers or an email to a supervisor: see [kl_log_head()].
#'
#' The assurance level is stated honestly and checked: work reviewed only by
#' the person who made it is `"self-reviewed"`, and a higher level needs a
#' named second person. The names are as typed; the check is a guard
#' against mislabeling, not proof of identity.
#'
#' One writer at a time: the log is a plain file, and two people appending
#' at the same moment on a shared drive can break the chain.
#'
#' @param what What was decided, e.g. `"Exclude duplicate intake records"`.
#' @param decision The decision itself, e.g. `"TAKE"`, `"approved"`, or a
#'   sentence.
#' @param by Who made it.
#' @param basis Why, in a sentence.
#' @param evidence Character vector of supporting references: files, work
#'   papers, URLs.
#' @param assurance `"self-reviewed"`, `"peer-reviewed"` or `"independent"`.
#' @param reviewed_by Who reviewed it. Required, and different from `by`,
#'   for anything above self-review.
#' @param ref Optional project id or review id the decision belongs to.
#' @param path Folder holding the layer.
#' @return The new entry's hash, invisibly.
#' @export
kl_log_decision <- function(what, decision, by, basis = "", evidence = character(),
                            assurance = assurance_levels, reviewed_by = "",
                            ref = "", path = kl_path()) {
  assurance <- match.arg(assurance)
  by <- trimws(by)
  reviewed_by <- trimws(reviewed_by)
  if (assurance != "self-reviewed" &&
      (!nzchar(reviewed_by) || tolower(reviewed_by) == tolower(by))) {
    stop("'", assurance, "' needs a reviewer other than the decision maker. ",
         "Record it as 'self-reviewed', or name reviewed_by.", call. = FALSE)
  }
  file <- file.path(kl_dir(path), "decisions.jsonl")
  lines <- read_utf8_lines(file)
  prev <- if (length(lines)) parse_entry(lines[length(lines)])$hash else "genesis"
  body <- list(
    seq = length(lines) + 1L, at = now_utc(), what = enc2utf8(what),
    decision = enc2utf8(decision), by = enc2utf8(by), reviewed_by = enc2utf8(reviewed_by),
    assurance = assurance, basis = enc2utf8(basis), evidence = as.list(enc2utf8(evidence)),
    ref = enc2utf8(ref), prev = prev
  )
  body_json <- enc2utf8(as.character(jsonlite::toJSON(body, auto_unbox = TRUE)))
  h <- kl_hash(body_json)
  line <- paste0(substr(body_json, 1, nchar(body_json) - 1), ',"hash":"', h, '"}\n')
  write_utf8(line, file, append = TRUE)
  invisible(h)
}

parse_entry <- function(line) {
  m <- regmatches(line, regexec('^(.*),"hash":"([^"]+)"\\}$', line))[[1]]
  if (length(m) != 3) return(list(body = NA_character_, hash = NA_character_))
  list(body = paste0(m[2], "}"), hash = m[3])
}

#' Read the decision log
#'
#' @param path Folder holding the layer.
#' @return A data frame, one row per decision, oldest first.
#' @export
kl_decisions <- function(path = kl_path()) {
  lines <- read_utf8_lines(file.path(kl_dir(path), "decisions.jsonl"))
  if (!length(lines)) {
    return(data.frame(seq = integer(), at = character(), what = character(),
                      decision = character(), by = character(), reviewed_by = character(),
                      assurance = character(), basis = character(), evidence = character(),
                      ref = character(), hash = character()))
  }
  do.call(rbind, lapply(lines, function(l) {
    e <- jsonlite::fromJSON(l, simplifyVector = FALSE)
    data.frame(seq = as.integer(e$seq), at = e$at, what = e$what,
               decision = e$decision, by = e$by, reviewed_by = e$reviewed_by %||% "",
               assurance = e$assurance, basis = e$basis,
               evidence = collapse(e$evidence), ref = e$ref %||% "", hash = e$hash)
  }))
}

#' The head of the decision log, for recording elsewhere
#'
#' The newest entry's number and hash. Copy it into the work papers, or
#' email it to a supervisor, at milestones such as a report going out. Later,
#' `kl_verify_log(expect_head = )` confirms the log still contains that
#' entry unchanged, which catches a rewritten file or removed entries that
#' the chain alone cannot.
#'
#' @param path Folder holding the layer.
#' @return A string `"<seq>:<hash>"`, also printed.
#' @export
kl_log_head <- function(path = kl_path()) {
  d <- kl_decisions(path)
  if (!nrow(d)) stop("The decision log is empty.", call. = FALSE)
  head <- paste0(d$seq[nrow(d)], ":", d$hash[nrow(d)])
  message("Record this outside the knowledge folder: ", head)
  invisible(head)
}

#' Verify the decision log
#'
#' Recomputes every entry's hash and checks each points at the one before,
#' which detects any edited, removed, inserted or reordered earlier entry.
#' With `expect_head`, it also confirms the log still contains an entry
#' recorded earlier with [kl_log_head()], which detects a rewritten file or
#' removed newest entries.
#'
#' @param path Folder holding the layer.
#' @param expect_head Optional `"<seq>:<hash>"` from [kl_log_head()].
#' @return `TRUE` invisibly when the log checks out. Otherwise an error
#'   naming the first entry that does not.
#' @export
kl_verify_log <- function(path = kl_path(), expect_head = NULL) {
  lines <- read_utf8_lines(file.path(kl_dir(path), "decisions.jsonl"))
  prev <- "genesis"
  hashes <- character(length(lines))
  for (i in seq_along(lines)) {
    e <- parse_entry(lines[i])
    if (is.na(e$hash)) stop("Entry ", i, " is malformed.", call. = FALSE)
    algo <- sub(":.*$", "", e$hash)
    if (!identical(kl_hash(e$body, algo = algo), e$hash)) {
      stop("Entry ", i, " was changed after it was written.", call. = FALSE)
    }
    if (!identical(jsonlite::fromJSON(e$body)$prev, prev)) {
      stop("Entry ", i, " does not follow entry ", i - 1,
           ": an entry was removed, reordered or inserted.", call. = FALSE)
    }
    prev <- hashes[i] <- e$hash
  }
  if (!is.null(expect_head)) {
    seq <- as.integer(sub(":.*$", "", expect_head))
    h <- sub("^[0-9]+:", "", expect_head)
    if (is.na(seq) || seq > length(lines)) {
      stop("The log has ", length(lines), " entries; the recorded head was entry ", seq,
           ". Entries have been removed since it was recorded.", call. = FALSE)
    }
    if (!identical(hashes[seq], h)) {
      stop("Entry ", seq, " no longer matches the head recorded for it: ",
           "the log has been rewritten since.", call. = FALSE)
    }
  }
  message("Decision log intact: ", length(lines), " entries",
          if (!is.null(expect_head)) ", including the recorded head" else "", ".")
  invisible(TRUE)
}
