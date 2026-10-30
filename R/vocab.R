# The shipped vocabulary is read once per session; the office's local layer
# is read fresh every time, because it changes.
vocab_cache <- new.env(parent = emptyenv())

shipped_vocab <- function() {
  if (is.null(vocab_cache$v)) {
    f <- system.file("extdata", "vocabulary.json", package = "knowledgelayer")
    vocab_cache$v <- jsonlite::read_json(f, simplifyVector = FALSE)
  }
  vocab_cache$v
}

local_vocab_file <- function(path) file.path(path, "knowledge", "vocabulary.json")

read_local_vocab <- function(path) {
  v <- read_json_file(local_vocab_file(path),
                      list(schema = "kl-vocabulary-local/1", concepts = list()))
  if (!identical(v$schema, "kl-vocabulary-local/1")) {
    stop("Not a local vocabulary file this version can read: ", local_vocab_file(path),
         call. = FALSE)
  }
  v$concepts <- v$concepts %||% list()
  v
}

# One concept as a list, whichever layer it came from.
all_concepts <- function(path) {
  shipped <- lapply(shipped_vocab()$concepts, function(k) c(k, source = "shipped"))
  local <- if (dir.exists(file.path(path, "knowledge"))) read_local_vocab(path)$concepts else list()
  local <- lapply(local, function(k) c(k, source = "local"))
  # Narrower is derived, so a local area placed under a shipped cluster shows
  # up under it without the shipped set being edited.
  all <- c(shipped, local)
  ids <- vapply(all, function(k) k$id, character(1))
  for (i in seq_along(all)) {
    kids <- ids[vapply(all, function(k) all[[i]]$id %in% unlist(k$broader), logical(1))]
    all[[i]]$narrower <- as.list(sort(unique(c(unlist(all[[i]]$narrower), kids))))
  }
  all
}

# Crosswalk precision, said plainly. Only a link to the exact item, principle
# or section is offered as a link to the point itself; a scheme-level or
# search link is labeled as what it is.
exact_precisions <- c("item", "principle", "section")

precision_label <- function(precision) {
  vapply(precision, function(p) {
    if (p %in% exact_precisions) paste("direct link to this", p)
    else if (identical(p, "scheme")) "link to the whole standard, not to this point"
    else if (identical(p, "search")) "link to a search page, not to this point"
    else "link of unstated precision, not to this point"
  }, character(1), USE.NAMES = FALSE)
}

#' The shared oversight vocabulary
#'
#' A controlled vocabulary for oversight work: audit and review concepts,
#' report types, kinds of criteria, a typology of findings with crosswalks to
#' the standards they relate to, and program areas. It ships with the
#' package (see `VOCABULARY.md` for where it came from and what was removed)
#' and an office adds its own terms in a local layer with
#' [kl_vocab_extend()] or [kl_vocab_import()]. The shipped set is never
#' edited.
#'
#' Concepts are identified by short ids such as `"ft:fraud-misappropriation"`.
#' The short ids are the stable identifiers: tags store them, never a URI,
#' so nothing anyone has tagged changes if the vocabulary is later given
#' permanent web names.
#'
#' @param scheme Optional scheme name, e.g. `"findings_typology"`.
#' @param path Folder holding the layer. If it has no knowledge layer, only
#'   the shipped vocabulary is returned.
#' @return A data frame, one row per concept, with columns `id`, `scheme`,
#'   `prefLabel`, `altLabels`, `broader`, `narrower`, `related` (each
#'   `"; "`-separated), `mappings` (crosswalks, `"; "`-separated, each with
#'   its precision), `scopeNote` and `source` (`"shipped"` or `"local"`).
#'   The vocabulary's provenance is in `attr(, "source")`.
#' @examples
#' v <- kl_vocab("findings_typology")
#' v[, c("id", "prefLabel")]
#' @export
kl_vocab <- function(scheme = NULL, path = kl_path()) {
  ks <- all_concepts(path)
  if (!is.null(scheme)) ks <- Filter(function(k) k$scheme %in% scheme, ks)
  out <- if (!length(ks)) {
    data.frame(id = character(), scheme = character(), prefLabel = character(),
               altLabels = character(), broader = character(), narrower = character(),
               related = character(), mappings = character(), scopeNote = character(),
               source = character())
  } else {
    do.call(rbind, lapply(ks, function(k) data.frame(
      id = k$id, scheme = k$scheme, prefLabel = k$prefLabel,
      altLabels = collapse(k$altLabels), broader = collapse(k$broader),
      narrower = collapse(k$narrower), related = collapse(k$related),
      mappings = collapse(vapply(k$mappings %||% list(), function(m)
        paste0(m$scheme, ": ", m$label, " (", m$precision, ")"), character(1))),
      scopeNote = k$scopeNote %||% "", source = k$source)))
  }
  attr(out, "source") <- shipped_vocab()$source
  out
}

# Crosswalks for one concept, as a data frame, with the precision said plainly.
kl_crosswalks <- function(id, path = kl_path()) {
  ks <- all_concepts(path)
  k <- Find(function(k) identical(k$id, id), ks)
  ms <- if (is.null(k)) list() else k$mappings %||% list()
  if (!length(ms)) {
    return(data.frame(scheme = character(), label = character(), uri = character(),
                      precision = character(), precision_label = character()))
  }
  d <- do.call(rbind, lapply(ms, function(m) data.frame(
    scheme = m$scheme, label = m$label, uri = m$uri, precision = m$precision)))
  d$precision_label <- precision_label(d$precision)
  d
}

norm_label <- function(x) tolower(gsub("\\s+", " ", trimws(x)))

#' Resolve free text to a concept
#'
#' Matches each term, ignoring case and extra spaces, against every
#' concept's id, preferred label and alternative labels (its synonym ring).
#' It never guesses: there is no partial or fuzzy matching, and a term that
#' matches more than one concept is reported as ambiguous with the
#' candidates, not settled by picking one. Narrow it with `scheme`. The
#' functions that store tags do this for you where the context settles it:
#' a finding's `typology` and a finding's tags resolve within the findings
#' typology.
#'
#' @param term Character vector of terms, e.g. `c("UoF", "fraud")`.
#' @param scheme Optional scheme(s) to search in.
#' @param path Folder holding the layer, for local terms.
#' @return A data frame, one row per term: `term`, `status` (`"match"`,
#'   `"ambiguous"` or `"no concept"`), `id`, `prefLabel` and `scheme` (`NA`
#'   unless matched), `matched_on` and `candidates` (the ids an ambiguous
#'   term matched).
#' @examples
#' kl_resolve(c("embezzlement", "segregation of duties", "parking tickets"))
#' @export
kl_resolve <- function(term, scheme = NULL, path = kl_path()) {
  stopifnot(is.character(term))
  ks <- all_concepts(path)
  if (!is.null(scheme)) ks <- Filter(function(k) k$scheme %in% scheme, ks)
  index <- do.call(rbind, c(list(data.frame(key = character(), id = character(),
                                            on = character())),
    lapply(ks, function(k) data.frame(
      key = norm_label(c(k$id, k$prefLabel, unlist(k$altLabels))),
      id = k$id,
      on = c("id", "prefLabel", rep("altLabel", length(unlist(k$altLabels))))))))
  rows <- lapply(term, function(t) {
    hit <- index[index$key == norm_label(t), , drop = FALSE]
    ids <- unique(hit$id)
    if (length(ids) == 1) {
      k <- Find(function(k) identical(k$id, ids), ks)
      data.frame(term = t, status = "match", id = ids, prefLabel = k$prefLabel,
                 scheme = k$scheme, matched_on = hit$on[1], candidates = "")
    } else {
      data.frame(term = t, status = if (length(ids)) "ambiguous" else "no concept",
                 id = NA_character_, prefLabel = NA_character_, scheme = NA_character_,
                 matched_on = "", candidates = paste(ids, collapse = "; "))
    }
  })
  if (!length(rows)) {
    return(data.frame(term = character(), status = character(), id = character(),
                      prefLabel = character(), scheme = character(),
                      matched_on = character(), candidates = character()))
  }
  do.call(rbind, rows)
}

# Resolve, and stop with every failure named, for functions that store ids.
resolve_or_stop <- function(terms, scheme = NULL, path = kl_path()) {
  terms <- unique(as.character(unlist(terms)))
  terms <- terms[nzchar(trimws(terms))]
  if (!length(terms)) return(character())
  r <- kl_resolve(terms, scheme = scheme, path = path)
  bad <- r[r$status != "match", , drop = FALSE]
  if (nrow(bad)) {
    why <- ifelse(bad$status == "ambiguous",
                  paste0("'", bad$term, "' is ambiguous (", bad$candidates, ")"),
                  paste0("'", bad$term, "': no concept"))
    stop("Not tagged, because a term did not resolve to exactly one concept: ",
         paste(why, collapse = "; "),
         ". Use a concept id, narrow with scheme =, or add the term with kl_vocab_extend().",
         call. = FALSE)
  }
  unique(r$id)
}

# The scheme a term resolves in when the context says what it must be: a
# finding's kind comes from the findings typology. NULL means every scheme.
context_scheme <- function(kind) {
  switch(kind, finding = "findings_typology", NULL)
}

id_pattern <- "^[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9._-]*$"

check_new_id <- function(id) {
  if (!grepl(id_pattern, id)) {
    stop("'", id, "' is not a short id. Use prefix:name, e.g. \"area:snow-removal\". ",
         "Concepts are named by short ids, never by URIs.", call. = FALSE)
  }
}

#' Add an office's own terms to the vocabulary
#'
#' Office-local terms (the city's own agencies, its own program areas, a
#' term its reports use) are kept in `knowledge/vocabulary.json`, layered
#' over the shipped vocabulary. The shipped set is never edited: an id that
#' is already shipped cannot be redefined locally. Calling again with a
#' local id updates that term.
#'
#' @param scheme Scheme to add to: a shipped scheme such as
#'   `"program_areas"`, or a new local one such as `"agencies"`.
#' @param id A short id, `prefix:name`, e.g. `"agency:streets"`. Never a URI.
#' @param prefLabel The preferred label.
#' @param altLabels Other names for the same thing: abbreviations, older
#'   names, what people actually say.
#' @param broader,related Ids of other concepts. Each must already exist,
#'   shipped or local.
#' @param scopeNote Optional note on what the term covers.
#' @param path Folder holding the layer.
#' @return The local layer as a data frame, invisibly.
#' @examples
#' root <- file.path(tempdir(), "example-city")
#' kl_init(root)
#' kl_vocab_extend("agencies", "agency:streets", "Department of Streets",
#'                 altLabels = "DoS", path = root)
#' @export
kl_vocab_extend <- function(scheme, id, prefLabel, altLabels = character(),
                            broader = character(), related = character(),
                            scopeNote = "", path = kl_path()) {
  stopifnot(is.character(scheme), length(scheme) == 1, grepl("^[a-z][a-z0-9_]*$", scheme),
            is.character(prefLabel), length(prefLabel) == 1, nzchar(trimws(prefLabel)))
  kl_dir(path)
  write_local_concepts(list(list(
    id = id, scheme = scheme, prefLabel = prefLabel, altLabels = as.list(altLabels),
    broader = as.list(broader), narrower = list(), related = as.list(related),
    scopeNote = scopeNote, mappings = list())), path)
  invisible(kl_vocab(path = path)[kl_vocab(path = path)$source == "local", , drop = FALSE])
}

# Validates every new concept before writing any of them, so a bad row never
# leaves the layer half-written.
write_local_concepts <- function(new, path) {
  shipped_ids <- vapply(shipped_vocab()$concepts, function(k) k$id, character(1))
  lv <- read_local_vocab(path)
  local_ids <- vapply(lv$concepts, function(k) k$id, character(1))
  new_ids <- vapply(new, function(k) k$id, character(1))
  for (k in new) check_new_id(k$id)
  taken <- intersect(new_ids, shipped_ids)
  if (length(taken)) {
    stop("Already in the shipped vocabulary, which is never edited: ",
         paste(taken, collapse = ", "), ". Choose a local id.", call. = FALSE)
  }
  if (anyDuplicated(new_ids)) stop("Duplicate ids: ", paste(unique(new_ids[duplicated(new_ids)]),
                                                         collapse = ", "), call. = FALSE)
  known <- c(shipped_ids, local_ids, new_ids)
  for (k in new) {
    refs <- c(unlist(k$broader), unlist(k$related))
    dangling <- setdiff(refs, known)
    if (length(dangling)) {
      stop("'", k$id, "' points at ", paste(dangling, collapse = ", "),
           ", which is not in the vocabulary. Add it first, or fix the id.", call. = FALSE)
    }
    if (k$id %in% refs) stop("'", k$id, "' cannot be its own broader or related.", call. = FALSE)
  }
  for (k in new) {
    i <- match(k$id, local_ids)
    if (is.na(i)) {
      lv$concepts[[length(lv$concepts) + 1]] <- k
      local_ids <- c(local_ids, k$id)
    } else {
      lv$concepts[[i]] <- k
    }
  }
  write_json_file(lv, local_vocab_file(path))
  invisible(new_ids)
}

#' Import an office's program areas from a spreadsheet
#'
#' Every office has program areas, and they are its own. This loads them
#' from a CSV file into the local layer, placed under the shipped top-level
#' clusters (see `kl_vocab("program_areas")`), and returns
#' [kl_vocab_check()] on the result.
#'
#' The file has the columns `id`, `prefLabel`, `altLabels` and `broader`.
#' Separate several alternative labels with `;`. Every `broader` must
#' resolve: to a shipped concept, a local one, or another row of the file.
#' If any row fails, nothing is imported.
#'
#' @param file Path to the CSV file.
#' @param scheme The scheme to import into.
#' @param path Folder holding the layer.
#' @return The result of [kl_vocab_check()].
#' @export
kl_vocab_import <- function(file, scheme = "program_areas", path = kl_path()) {
  kl_dir(path)
  d <- utils::read.csv(file, colClasses = "character", na.strings = character(),
                       fileEncoding = "UTF-8", check.names = FALSE)
  need <- c("id", "prefLabel", "altLabels", "broader")
  miss <- setdiff(need, names(d))
  if (length(miss)) {
    stop("The file needs the columns ", paste(need, collapse = ", "), "; missing: ",
         paste(miss, collapse = ", "), call. = FALSE)
  }
  d[] <- lapply(d, trimws)
  if (!nrow(d)) stop("The file has no rows.", call. = FALSE)
  empty <- which(!nzchar(d$id) | !nzchar(d$prefLabel))
  if (length(empty)) stop("Row(s) ", paste(empty, collapse = ", "), " need an id and a prefLabel.",
                          call. = FALSE)
  if (scheme == "program_areas") {
    nob <- d$id[!nzchar(d$broader)]
    if (length(nob)) {
      stop("Every program area goes under a cluster or another area; no broader for: ",
           paste(nob, collapse = ", "), call. = FALSE)
    }
  }
  split_labels <- function(x) {
    x <- trimws(strsplit(x, ";", fixed = TRUE)[[1]])
    as.list(x[nzchar(x)])
  }
  new <- lapply(seq_len(nrow(d)), function(i) list(
    id = d$id[i], scheme = scheme, prefLabel = d$prefLabel[i],
    altLabels = split_labels(d$altLabels[i]),
    broader = if (nzchar(d$broader[i])) list(d$broader[i]) else list(),
    narrower = list(), related = list(), scopeNote = "", mappings = list()))
  write_local_concepts(new, path)
  kl_vocab_check(path)
}

#' Check the vocabulary for problems
#'
#' Looks at the shipped vocabulary and the office's local layer together
#' for dangling ids (a broader, narrower or related id that is not in the
#' vocabulary), cycles in the broader hierarchy, and duplicate labels: the
#' same label on two concepts in one scheme (an error, because a search
#' cannot tell them apart), or in two schemes (a warning: often intended,
#' such as an audit as an activity and an audit as a kind of report, and
#' resolved with `scheme =`).
#'
#' @param path Folder holding the layer.
#' @return A data frame of problems (`id`, `level`, `problem`) with class
#'   `kl_vocab_check`, printed with an overall `PASS`, `PASS WITH WARNINGS`
#'   or `FAIL`.
#' @examples
#' kl_vocab_check(tempdir())
#' @export
kl_vocab_check <- function(path = kl_path()) {
  ks <- all_concepts(path)
  ids <- vapply(ks, function(k) k$id, character(1))
  out <- list()
  add <- function(id, level, problem) {
    out[[length(out) + 1]] <<- data.frame(id = id, level = level, problem = problem)
  }
  dups <- ids[duplicated(ids)]
  for (i in unique(dups)) add(i, "error", "id defined more than once")
  for (k in ks) {
    for (rel in c("broader", "narrower", "related")) {
      dangling <- setdiff(unlist(k[[rel]]), ids)
      for (x in dangling) add(k$id, "error", paste0(rel, " id '", x, "' is not in the vocabulary"))
    }
  }
  # Cycles: follow broader links from every concept; meeting the start again
  # is a cycle.
  parents <- lapply(ks, function(k) intersect(unlist(k$broader), ids))
  names(parents) <- ids
  in_cycle <- character()
  for (start in ids) {
    seen <- character()
    frontier <- parents[[start]]
    while (length(frontier)) {
      if (start %in% frontier) { in_cycle <- c(in_cycle, start); break }
      frontier <- setdiff(frontier, seen)
      seen <- c(seen, frontier)
      frontier <- unique(unlist(parents[frontier]))
    }
  }
  for (i in in_cycle) add(i, "error", "is its own broader concept, through a cycle")
  labs <- do.call(rbind, lapply(ks, function(k) data.frame(
    key = norm_label(c(k$prefLabel, unlist(k$altLabels))), id = k$id, scheme = k$scheme)))
  labs <- unique(labs)
  for (key in unique(labs$key[duplicated(labs$key)])) {
    hit <- labs[labs$key == key, , drop = FALSE]
    if (length(unique(hit$id)) < 2) next
    same <- any(duplicated(hit$scheme))
    add(paste(unique(hit$id), collapse = ", "), if (same) "error" else "warning",
        paste0("label '", key, "' is on more than one concept",
               if (same) " in the same scheme" else " (different schemes)"))
  }
  res <- if (length(out)) do.call(rbind, out) else
    data.frame(id = character(), level = character(), problem = character())
  structure(res, class = c("kl_vocab_check", "data.frame"), n_concepts = length(ks))
}

#' @export
print.kl_vocab_check <- function(x, ...) {
  result <- if (any(x$level == "error")) "FAIL" else
    if (nrow(x)) "PASS WITH WARNINGS" else "PASS"
  cat("Vocabulary check:", result, "|", attr(x, "n_concepts"), "concepts |",
      sum(x$level == "error"), "errors,", sum(x$level == "warning"), "warnings\n")
  if (any(x$level == "error")) {
    df <- x[x$level == "error", , drop = FALSE]
    class(df) <- "data.frame"
    print(df, row.names = FALSE)
  }
  if (any(x$level == "warning")) cat("Warnings: see the returned data frame.\n")
  invisible(x)
}

tags_file <- function(path) file.path(kl_dir(path), "tags.json")

read_tags <- function(path) {
  t <- read_json_file(tags_file(path), list(schema = "kl-tags/1", tags = list()))
  if (!identical(t$schema, "kl-tags/1")) {
    stop("Not a tags file this version can read: ", tags_file(path), call. = FALSE)
  }
  t$tags <- t$tags %||% list()
  t
}

#' Tag a project, finding or decision with concepts
#'
#' Tags are what connect work described in different words: a project
#' tagged `concept:procurement` is found by a search for "contracting". Each
#' term is resolved with [kl_resolve()] and stored as its short id. A term
#' that does not resolve to exactly one concept is refused, with the reason,
#' and nothing is tagged.
#'
#' Terms resolve in context. A finding is tagged from the findings typology
#' only, so "improper payment" means `ft:improper-payments` there, though on
#' its own it could also be a program area. Projects and decisions resolve
#' across every scheme unless `scheme` says otherwise.
#'
#' @param kind `"project"`, `"finding"` or `"decision"`.
#' @param id The project id, finding id, or decision number (`seq`) or hash.
#'   A project or decision must already exist.
#' @param concepts Concept ids or labels, e.g. `c("fraud", "ft:noncompliance")`.
#' @param scheme The scheme(s) to resolve in. By default `"findings_typology"`
#'   for a finding and every scheme otherwise; for example, `"program_areas"`
#'   tags a project with its program area.
#' @param path Folder holding the layer.
#' @return All tags as a data frame, invisibly.
#' @export
kl_tag <- function(kind = c("project", "finding", "decision"), id, concepts,
                   scheme = NULL, path = kl_path()) {
  kind <- match.arg(kind)
  if (is.null(scheme)) scheme <- context_scheme(kind)
  stopifnot(is.character(id) || is.numeric(id), length(id) == 1)
  id <- as.character(id)
  if (kind == "project" && !id %in% kl_projects(path)$id) {
    stop("Not registered: ", id, ". Add with kl_add_project() first.", call. = FALSE)
  }
  if (kind == "decision") {
    d <- kl_decisions(path)
    if (!id %in% c(as.character(d$seq), d$hash)) stop("No decision ", id, " in the log.", call. = FALSE)
  }
  ids <- resolve_or_stop(concepts, scheme = scheme, path = path)
  t <- read_tags(path)
  have <- vapply(t$tags, function(x) paste(x$kind, x$id, x$concept), character(1))
  for (cid in ids) {
    if (!paste(kind, id, cid) %in% have) {
      t$tags[[length(t$tags) + 1]] <- list(kind = kind, id = id, concept = cid, added = now_utc())
    }
  }
  write_json_file(t, tags_file(path))
  invisible(kl_tags(path = path))
}

#' List tags
#'
#' @param kind Optional `"project"`, `"finding"` or `"decision"`.
#' @param id Optional id to filter to.
#' @param path Folder holding the layer.
#' @return A data frame of tags: `kind`, `id`, `concept`, `prefLabel`, `added`.
#' @export
kl_tags <- function(kind = NULL, id = NULL, path = kl_path()) {
  t <- read_tags(path)$tags
  d <- if (!length(t)) {
    data.frame(kind = character(), id = character(), concept = character(), added = character())
  } else {
    do.call(rbind, lapply(t, function(x) data.frame(kind = x$kind, id = x$id,
                                                    concept = x$concept, added = x$added)))
  }
  if (!is.null(kind)) d <- d[d$kind == kind, , drop = FALSE]
  if (!is.null(id)) d <- d[d$id == as.character(id), , drop = FALSE]
  v <- kl_vocab(path = path)
  d$prefLabel <- v$prefLabel[match(d$concept, v$id)]
  rownames(d) <- NULL
  d[, c("kind", "id", "concept", "prefLabel", "added")]
}

ttl_string <- function(x) {
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\"", "\\\"", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  paste0("\"", x, "\"@en")
}

ttl_plain <- function(x) sub("@en$", "", ttl_string(x))

ttl_iri <- function(base, id) {
  parts <- strsplit(id, ":", fixed = TRUE)[[1]]
  paste0("<", base, paste(vapply(parts, utils::URLencode, character(1), reserved = TRUE),
                          collapse = "/"), ">")
}

#' Export the vocabulary as SKOS (Turtle)
#'
#' Writes the shipped vocabulary and the office's local terms as a SKOS
#' concept scheme in Turtle, for loading into any linked-data tool.
#' Optionally, projects are included as resources with `dct:subject`
#' pointing at the concepts they are tagged with.
#'
#' The package bakes in no web address for its concepts: the short ids are
#' the stable identifiers. So `base` is required and has no default:
#' whoever exports chooses the namespace, e.g.
#' `"https://data.example.org/vocab/"`. A concept `ft:noncompliance` becomes
#' `<base>ft/noncompliance`.
#'
#' A crosswalk to an exact item, principle or section is written as a SKOS
#' mapping (`skos:closeMatch` and so on). A crosswalk to a whole standard or
#' a search page is written as `rdfs:seeAlso`, because asserting it as a
#' match would claim more precision than it has.
#'
#' @param file Where to write the `.ttl` file.
#' @param base The namespace for concept IRIs: an `http` or `https` address
#'   ending in `/` or `#`. Required.
#' @param projects Also export registered projects and their tags.
#' @param path Folder holding the layer.
#' @return The file path, invisibly.
#' @export
kl_export_skos <- function(file, base, projects = FALSE, path = kl_path()) {
  if (missing(base) || !is.character(base) || length(base) != 1 || is.na(base) ||
      !grepl("^https?://[^[:space:]<>\"]+[/#]$", base)) {
    stop("kl_export_skos() needs `base`, the web namespace for the concepts, such as ",
         "\"https://data.example.org/vocab/\" (ending in / or #). The package has no default: ",
         "the short ids are the stable identifiers, and whoever exports chooses the namespace.",
         call. = FALSE)
  }
  ks <- all_concepts(path)
  schemes <- unique(vapply(ks, function(k) k$scheme, character(1)))
  stext <- shipped_vocab()$schemes
  out <- c("@prefix skos: <http://www.w3.org/2004/02/skos/core#> .",
           "@prefix dct: <http://purl.org/dc/terms/> .",
           "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .", "")
  for (s in schemes) {
    out <- c(out, paste0(ttl_iri(base, paste0("scheme:", s)), " a skos:ConceptScheme ;"),
             paste0("  skos:prefLabel ", ttl_string(stext[[s]]$label %||% s), " ."), "")
  }
  rel_map <- c(exactMatch = "skos:exactMatch", closeMatch = "skos:closeMatch",
               relatedMatch = "skos:relatedMatch", broadMatch = "skos:broadMatch",
               narrowMatch = "skos:narrowMatch")
  for (k in ks) {
    p <- c(paste0("  skos:inScheme ", ttl_iri(base, paste0("scheme:", k$scheme))),
           paste0("  skos:notation ", ttl_plain(k$id)),
           paste0("  skos:prefLabel ", ttl_string(k$prefLabel)))
    for (a in unlist(k$altLabels)) p <- c(p, paste0("  skos:altLabel ", ttl_string(a)))
    if (nzchar(k$scopeNote %||% "")) p <- c(p, paste0("  skos:scopeNote ", ttl_string(k$scopeNote)))
    if (!length(unlist(k$broader))) {
      p <- c(p, paste0("  skos:topConceptOf ", ttl_iri(base, paste0("scheme:", k$scheme))))
    }
    for (rel in c("broader", "narrower", "related")) {
      for (x in unlist(k[[rel]])) p <- c(p, paste0("  skos:", rel, " ", ttl_iri(base, x)))
    }
    for (m in k$mappings %||% list()) {
      pred <- if (m$precision %in% exact_precisions && m$type %in% names(rel_map))
        rel_map[[m$type]] else "rdfs:seeAlso"
      p <- c(p, paste0("  ", pred, " <", m$uri, ">"))
    }
    out <- c(out, paste0(ttl_iri(base, k$id), " a skos:Concept ;"),
             paste0(p, c(rep(" ;", length(p) - 1), " .")), "")
  }
  if (projects) {
    pr <- kl_projects(path)
    tg <- kl_tags("project", path = path)
    for (i in seq_len(nrow(pr))) {
      subj <- unique(c(tg$concept[tg$id == pr$id[i]],
                       strsplit(pr$concepts[i], "; ", fixed = TRUE)[[1]]))
      subj <- subj[nzchar(subj)]
      p <- c(paste0("  dct:identifier ", ttl_plain(pr$id[i])),
             paste0("  dct:title ", ttl_string(pr$title[i])),
             if (length(subj)) paste0("  dct:subject ", vapply(subj, ttl_iri, character(1),
                                                              base = base, USE.NAMES = FALSE)))
      out <- c(out, paste0(ttl_iri(base, paste0("project:", pr$id[i])), " a dct:BibliographicResource ;"),
               paste0(p, c(rep(" ;", length(p) - 1), " .")), "")
    }
  }
  write_utf8(out, ensure_dir(file))
  invisible(file)
}
