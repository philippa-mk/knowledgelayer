#' Open the runbook
#'
#' A step-by-step guide to the package in a self-contained web page:
#' install and IT approval, setting up the knowledge folder, running a
#' review end to end, gating a pipeline, and adding version control.
#'
#' @param browse Open it in the default browser. If `FALSE`, just return
#'   the path, e.g. to copy the file to a colleague.
#' @return The path to the runbook, invisibly.
#' @export
kl_runbook <- function(browse = interactive()) {
  f <- system.file("runbook", "runbook.html", package = "knowledgelayer")
  if (browse) utils::browseURL(f)
  invisible(f)
}

#' Start a knowledge layer
#'
#' Creates a `knowledge/` folder holding plain text files: a project
#' registry (`projects.json`), the links between projects (`links.csv`), an
#' append-only decision log (`decisions.jsonl`) and a `handoffs/` folder.
#' Every file is human-readable and diffs cleanly, so the layer works on a
#' shared drive today and moves into version control unchanged whenever the
#' office adopts it.
#'
#' @param path Folder to hold the layer, usually the root of a shared drive
#'   or of an RStudio project. Defaults to the working directory.
#' @return The path to the `knowledge/` folder, invisibly.
#' @examples
#' root <- file.path(tempdir(), "office")
#' kl_init(root)
#' @export
kl_init <- function(path = kl_path()) {
  d <- file.path(path, "knowledge")
  dir.create(file.path(d, "handoffs"), recursive = TRUE, showWarnings = FALSE)
  if (!file.exists(file.path(d, "projects.json"))) {
    write_json_file(list(schema = projects_schema, projects = list()),
                    file.path(d, "projects.json"))
  }
  if (!file.exists(file.path(d, "links.csv"))) {
    utils::write.csv(empty_links(), file.path(d, "links.csv"), row.names = FALSE,
                     fileEncoding = "UTF-8")
  }
  if (!file.exists(file.path(d, "decisions.jsonl"))) {
    file.create(file.path(d, "decisions.jsonl"))
  }
  invisible(d)
}

#' Register a project, or update one already registered
#'
#' One entry per piece of work: an annual report, a recurring data pull, a
#' one-off review. The point is to write down, while it is fresh, what a
#' colleague would need if the person who built it were out tomorrow.
#'
#' @param id Short, stable identifier, e.g. `"annual-report-2026"`. Never
#'   reuse one: links and decisions point at it.
#' @param title Plain-language name.
#' @param owner The person accountable for it.
#' @param people Everyone who could run or explain it, owner included.
#' @param status One of `"active"`, `"paused"`, `"done"`, `"archived"`.
#' @param sources Data sources it reads, e.g. `"Complaint intake records"`.
#' @param methods Methods or scripts it relies on.
#' @param outputs What it produces.
#' @param location Where the code and work papers live.
#' @param notes Anything else a successor must know.
#' @param concepts Concepts it is about: ids or labels from [kl_vocab()],
#'   e.g. `c("procurement", "ft:improper-payments")`. Each is resolved with
#'   [kl_resolve()] and stored as its short id; a term that does not resolve
#'   to exactly one concept is refused.
#' @param path Folder holding the layer.
#' @return The registry as a data frame, invisibly.
#' @export
kl_add_project <- function(id, title, owner, people = owner,
                           status = c("active", "paused", "done", "archived"),
                           sources = character(), methods = character(),
                           outputs = character(), location = "", notes = "",
                           concepts = character(), path = kl_path()) {
  status <- match.arg(status)
  stopifnot(is.character(id), length(id) == 1, nzchar(id))
  file <- file.path(kl_dir(path), "projects.json")
  reg <- read_registry(file)
  ids <- vapply(reg$projects, function(p) p$id, character(1))
  entry <- list(
    id = id, title = title, owner = owner,
    people = as.list(unique(c(owner, people))), status = status,
    sources = as.list(sources), methods = as.list(methods),
    outputs = as.list(outputs), location = location, notes = notes,
    concepts = as.list(resolve_or_stop(concepts, path = path)),
    updated = now_utc()
  )
  if (id %in% ids) {
    entry$registered <- reg$projects[[match(id, ids)]]$registered
    reg$projects[[match(id, ids)]] <- entry
  } else {
    entry$registered <- entry$updated
    reg$projects[[length(reg$projects) + 1]] <- entry
  }
  write_json_file(reg, file)
  invisible(kl_projects(path))
}

#' List registered projects
#'
#' @param path Folder holding the layer.
#' @return A data frame, one row per project. List fields are collapsed to
#'   `"; "`-separated text; `n_people` counts who can run each project.
#' @export
kl_projects <- function(path = kl_path()) {
  reg <- read_registry(file.path(kl_dir(path), "projects.json"))
  if (length(reg$projects) == 0) {
    return(data.frame(id = character(), title = character(), owner = character(),
                      status = character(), n_people = integer(), people = character(),
                      sources = character(), methods = character(), outputs = character(),
                      location = character(), concepts = character(), updated = character()))
  }
  do.call(rbind, lapply(reg$projects, function(p) data.frame(
    id = p$id, title = p$title, owner = p$owner, status = p$status,
    n_people = length(p$people), people = collapse(p$people),
    sources = collapse(p$sources), methods = collapse(p$methods),
    outputs = collapse(p$outputs), location = p$location %||% "",
    concepts = collapse(p$concepts), updated = p$updated
  )))
}

projects_schema <- "kl-projects/2"

# Files written by an earlier version load unchanged and are upgraded in
# memory; the upgrade reaches the disk the next time the registry is
# written. A file from a newer version is refused rather than misread.
read_registry <- function(file) {
  reg <- read_json_file(file, list(schema = projects_schema, projects = list()))
  migrate_registry(reg, file)
}

migrate_registry <- function(reg, file = "projects.json") {
  schema <- reg$schema %||% "kl-projects/1"
  if (identical(schema, "kl-projects/1")) {
    reg$projects <- lapply(reg$projects %||% list(), function(p) {
      p$concepts <- p$concepts %||% list()
      p
    })
    schema <- projects_schema
  }
  if (!identical(schema, projects_schema)) {
    stop("'", file, "' is '", schema, "', which this version of knowledgelayer cannot read. ",
         "Update the package.", call. = FALSE)
  }
  reg$schema <- projects_schema
  reg$projects <- reg$projects %||% list()
  reg
}

empty_links <- function() {
  data.frame(from = character(), to = character(), relation = character(),
             note = character(), added = character())
}

#' Record how two projects connect
#'
#' Links are what turn a list of projects into a knowledge layer: they show
#' that this year's report reuses last year's cleaning code, or that two
#' teams draw on the same extract and should agree on one definition.
#'
#' @param from,to Project ids. Both must already be registered.
#' @param relation One of `"uses-data-from"`, `"reuses-code-from"`,
#'   `"shares-method-with"`, `"informs"`, `"supersedes"`, or one of the SKOS
#'   relations `"broader"` (`from` is part of the wider piece of work `to`),
#'   `"narrower"` (the reverse) and `"related"`.
#' @param note Optional detail.
#' @param path Folder holding the layer.
#' @return All links as a data frame, invisibly.
#' @export
kl_link <- function(from, to,
                    relation = c("uses-data-from", "reuses-code-from",
                                 "shares-method-with", "informs", "supersedes",
                                 "broader", "narrower", "related"),
                    note = "", path = kl_path()) {
  relation <- match.arg(relation)
  known <- kl_projects(path)$id
  missing <- setdiff(c(from, to), known)
  if (length(missing)) {
    stop("Not registered: ", paste(missing, collapse = ", "),
         ". Add with kl_add_project() first.", call. = FALSE)
  }
  file <- file.path(kl_dir(path), "links.csv")
  links <- kl_links(path)
  dup <- links$from == from & links$to == to & links$relation == relation
  if (!any(dup)) {
    links <- rbind(links, data.frame(from = from, to = to, relation = relation,
                                     note = note, added = now_utc()))
    utils::write.csv(links, file, row.names = FALSE, fileEncoding = "UTF-8")
  }
  invisible(links)
}

#' List links between projects
#'
#' @param path Folder holding the layer.
#' @param id Optional project id; returns only links touching it.
#' @return A data frame of links.
#' @export
kl_links <- function(path = kl_path(), id = NULL) {
  file <- file.path(kl_dir(path), "links.csv")
  links <- if (file.exists(file)) {
    utils::read.csv(file, colClasses = "character", fileEncoding = "UTF-8")
  } else {
    empty_links()
  }
  if (!is.null(id)) links <- links[links$from == id | links$to == id, , drop = FALSE]
  links
}

#' Search the knowledge layer
#'
#' Case-insensitive, literal-text search across every project field. Use it to answer
#' "has anyone here already worked with this data?" before starting again.
#'
#' Search goes through the vocabulary's synonyms: if the term resolves to a
#' concept (see [kl_resolve()]), every label of that concept is searched
#' too, and projects tagged with it are found whatever words they use. So a
#' search for "UoF" finds the "use of force extract". A term that does not
#' resolve, or is ambiguous, is searched literally, as before.
#'
#' @param term Text to look for.
#' @param path Folder holding the layer.
#' @return Matching projects as a data frame.
#' @export
kl_find <- function(term, path = kl_path()) {
  p <- kl_projects(path)
  if (nrow(p) == 0) return(p)
  synonyms <- character()
  tagged <- character()
  r <- kl_resolve(term, path = path)
  if (identical(r$status, "match")) {
    v <- kl_vocab(path = path)
    k <- v[v$id == r$id, ]
    labels <- c(k$prefLabel, strsplit(k$altLabels, "; ", fixed = TRUE)[[1]])
    synonyms <- setdiff(unique(tolower(labels[nzchar(labels)])), tolower(term))
    tg <- if (file.exists(file.path(kl_dir(path), "tags.json"))) kl_tags("project", path = path) else NULL
    tagged <- c(tg$id[tg$concept == r$id], p$id[vapply(strsplit(p$concepts, "; ", fixed = TRUE),
                                                     function(x) r$id %in% x, logical(1))])
  }
  hay <- tolower(apply(p, 1, paste, collapse = " "))
  # The term itself matches anywhere, as in v0.1; a synonym only as whole
  # words, so a short one such as "IC" does not match "public".
  whole <- function(t) paste0("(^|[^[:alnum:]])", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", t),
                              "($|[^[:alnum:]])")
  hit <- grepl(tolower(term), hay, fixed = TRUE) | p$id %in% tagged
  for (t in synonyms) hit <- hit | grepl(whole(t), hay)
  p[hit, , drop = FALSE]
}

#' Find single points of knowledge
#'
#' A single point of knowledge is work that only one person (or very few)
#' could run or explain. This flags live projects that only `max_people`
#' people can run, and says whether each has a written handoff. A project with one person and no
#' handoff is the one to fix first.
#'
#' @param max_people Flag projects with this many people or fewer.
#' @param path Folder holding the layer.
#' @return A data frame of flagged projects, most exposed first.
#' @export
kl_single_points <- function(max_people = 1, path = kl_path()) {
  p <- kl_projects(path)
  p <- p[p$status %in% c("active", "paused") & p$n_people <= max_people, , drop = FALSE]
  if (nrow(p) == 0) return(cbind(p, has_handoff = logical(), dependents = integer()))
  hand <- list.files(file.path(kl_dir(path), "handoffs"))
  links <- kl_links(path)
  p$has_handoff <- vapply(p$id, function(i) any(startsWith(hand, paste0(i, "_"))), logical(1))
  p$dependents <- vapply(p$id, function(i) sum(links$to == i), integer(1))
  p <- p[order(p$has_handoff, -p$dependents), , drop = FALSE]
  rownames(p) <- NULL
  p[, c("id", "title", "owner", "n_people", "has_handoff", "dependents")]
}

#' Write a handoff note for a project
#'
#' Drafts a dated Markdown note from what the registry, the links and the
#' decision log already know, leaving clearly marked gaps for the parts only
#' the person handing over can fill in.
#'
#' @param id Project id.
#' @param path Folder holding the layer.
#' @return Path to the new note, invisibly.
#' @export
kl_handoff <- function(id, path = kl_path()) {
  p <- kl_projects(path)
  if (!id %in% p$id) stop("Not registered: ", id, call. = FALSE)
  p <- p[p$id == id, ]
  links <- kl_links(path, id)
  dec <- kl_decisions(path)
  dec <- dec[dec$ref == id, , drop = FALSE]
  fmt_links <- if (nrow(links)) {
    paste0("- ", links$from, " ", links$relation, " ", links$to,
           ifelse(nzchar(links$note), paste0(" (", links$note, ")"), ""))
  } else "- none recorded"
  fmt_dec <- if (nrow(dec)) {
    paste0("- ", substr(dec$at, 1, 10), " ", dec$what, ": ", dec$decision,
           " (", dec$by, ", ", dec$assurance, ")")
  } else "- none recorded"
  board <- kl_board(project = id, path = path)
  fmt_board <- if (nrow(board)) {
    paste0("- [", board$list, ifelse(nzchar(board$status), paste0(": ", board$status), ""),
           "] ", board$text, ifelse(board$stale, " (parked 3+ triages)", ""))
  } else "- nothing on the board"
  todo <- "_To fill in:_"
  lines <- c(
    paste0("# Handoff: ", p$title), "",
    paste0("Project `", id, "` | owner ", p$owner, " | status ", p$status,
           " | written ", format(Sys.Date())), "",
    paste("> The test of a good handoff: could someone new, reading only this,",
          "make the right next move without asking anything?"), "",
    "## Where we are", todo, "",
    "## Where it lives", if (nzchar(p$location)) p$location else todo, "",
    "## Data sources", if (nzchar(p$sources)) p$sources else todo, "",
    "## Methods", if (nzchar(p$methods)) p$methods else todo, "",
    "## Outputs", if (nzchar(p$outputs)) p$outputs else todo, "",
    "## Connected projects", fmt_links, "",
    "## Decisions and why (don't reopen these)", fmt_dec,
    paste(todo, "the reasons behind any decision above that are not recorded.",
          "What was done is easy to rebuild; why is what gets lost."), "",
    "## Tried, didn't work (don't repeat)", todo, "",
    "## How to run it from scratch", todo, "",
    "## Next steps (start here)", todo, "",
    "## Watch out", todo, "",
    "## Board", fmt_board, ""
  )
  file <- file.path(kl_dir(path), "handoffs",
                    paste0(id, "_", format(Sys.Date()), ".md"))
  write_utf8(c(lines, ""), file)
  invisible(file)
}
