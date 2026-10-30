board_file <- function(path) file.path(kl_dir(path), "board.json")

read_board <- function(path) {
  b <- read_json_file(board_file(path), list(schema = "kl-board/1", items = list()))
  b$items <- b$items %||% list()
  b
}

#' Note an idea without committing to it
#'
#' Adds an item to a project's Inbox. The Inbox exists so that "we should
#' also..." can be written down the moment it comes up, without landing on
#' the plan. Nothing reaches the Roadmap except through [kl_triage()].
#'
#' @param text The idea, worry or task, in a line.
#' @param project Project id it belongs to (need not be registered).
#' @param by Who raised it.
#' @param path Folder holding the layer.
#' @return The new item's id, invisibly.
#' @export
kl_inbox <- function(text, project, by = "", path = kl_path()) {
  b <- read_board(path)
  id <- sprintf("i%03d", length(b$items) + 1L)
  b$items[[length(b$items) + 1]] <- list(
    id = id, project = project, text = text, by = by, list = "inbox",
    status = "", parked = 0L, added = now_utc(), updated = now_utc())
  write_json_file(b, board_file(path))
  invisible(id)
}

#' Triage the Inbox and Parking lot
#'
#' A person rules on each item: `TAKE` puts it on the Roadmap, `HOLD` parks
#' it, `DROP` lets it go (and records that in the decision log, so the idea
#' is not raised again from scratch), `DISCUSS` leaves it where it is.
#'
#' Before parking anything, ask: will other work have to be redone if this
#' comes later? If so, it is a foundation, and belongs on the Roadmap now.
#'
#' @param ids Item ids, e.g. `c("i001", "i002")`.
#' @param decisions One of `"TAKE"`, `"HOLD"`, `"DROP"`, `"DISCUSS"` per id.
#' @param by Who decided.
#' @param reasons Optional one-line reason per id; recorded for `HOLD` and
#'   `DROP`.
#' @param path Folder holding the layer.
#' @return The board for the projects touched, invisibly.
#' @export
kl_triage <- function(ids, decisions, by, reasons = "", path = kl_path()) {
  decisions <- toupper(decisions)
  bad <- setdiff(decisions, c("TAKE", "HOLD", "DROP", "DISCUSS"))
  if (length(bad)) stop("Unknown triage decision: ", paste(bad, collapse = ", "), call. = FALSE)
  stopifnot(length(ids) == length(decisions))
  reasons <- rep_len(reasons, length(ids))
  b <- read_board(path)
  have <- vapply(b$items, function(x) x$id, character(1))
  # Validate every id before changing anything, so a bad id never leaves
  # the board and the decision log disagreeing.
  idx <- match(ids, have)
  if (anyNA(idx)) stop("No board item: ", paste(ids[is.na(idx)], collapse = ", "), call. = FALSE)
  for (i in idx) {
    if (!b$items[[i]]$list %in% c("inbox", "parking")) {
      stop("'", b$items[[i]]$id, "' is already on the ", b$items[[i]]$list,
           "; triage covers the Inbox and Parking lot.", call. = FALSE)
    }
  }
  drops <- list()
  for (k in seq_along(ids)) {
    i <- idx[k]
    it <- b$items[[i]]
    switch(decisions[k],
      TAKE = { it$list <- "roadmap"; it$status <- "to do" },
      HOLD = { it$list <- "parking"; it$parked <- as.integer(it$parked) + 1L; it$reason <- reasons[k] },
      DROP = {
        it$list <- "dropped"
        drops[[length(drops) + 1]] <- list(text = it$text, reason = reasons[k], project = it$project)
      },
      DISCUSS = NULL
    )
    it$updated <- now_utc()
    b$items[[i]] <- it
  }
  write_json_file(b, board_file(path))
  for (d in drops) {
    kl_log_decision(paste("Drop board item:", d$text), "DROP", by = by,
                    basis = d$reason, ref = d$project, path = path)
  }
  invisible(kl_board(path = path))
}

#' Update a Roadmap item's status
#'
#' @param id Item id.
#' @param status `"to do"`, `"doing"`, `"done"` or `"stuck"`.
#' @param checked For `"done"`: how you know it works. Required, because
#'   done means verified, not drafted.
#' @param path Folder holding the layer.
#' @export
kl_roadmap_status <- function(id, status = c("to do", "doing", "done", "stuck"),
                              checked = "", path = kl_path()) {
  status <- match.arg(status)
  if (status == "done" && !nzchar(checked)) {
    stop("Say how you know it works: kl_roadmap_status(id, \"done\", checked = \"...\").",
         call. = FALSE)
  }
  b <- read_board(path)
  i <- match(id, vapply(b$items, function(x) x$id, character(1)))
  if (is.na(i) || b$items[[i]]$list != "roadmap") {
    stop("'", id, "' is not on the Roadmap.", call. = FALSE)
  }
  b$items[[i]]$status <- status
  b$items[[i]]$checked <- checked
  b$items[[i]]$updated <- now_utc()
  write_json_file(b, board_file(path))
  invisible(kl_board(path = path))
}

#' Show the Board
#'
#' Three short lists per project: Inbox (new, unsorted), Roadmap (decided,
#' with a status) and Parking lot (good, not now). Items parked through
#' three triages are flagged `stale`: they are probably not happening, and
#' dropping them is fine.
#'
#' @param project Optional project id to filter to.
#' @param include_dropped Also show dropped items.
#' @param path Folder holding the layer.
#' @return A data frame of board items, Roadmap first.
#' @export
kl_board <- function(project = NULL, include_dropped = FALSE, path = kl_path()) {
  b <- read_board(path)
  if (!length(b$items)) {
    return(data.frame(id = character(), project = character(), list = character(),
                      status = character(), text = character(), stale = logical()))
  }
  d <- do.call(rbind, lapply(b$items, function(x) data.frame(
    id = x$id, project = x$project, list = x$list, status = x$status %||% "",
    text = x$text, stale = x$list == "parking" && as.integer(x$parked) >= 3)))
  if (!is.null(project)) d <- d[d$project == project, , drop = FALSE]
  if (!include_dropped) d <- d[d$list != "dropped", , drop = FALSE]
  d <- d[order(match(d$list, c("roadmap", "inbox", "parking", "dropped")), d$id), , drop = FALSE]
  rownames(d) <- NULL
  d
}
