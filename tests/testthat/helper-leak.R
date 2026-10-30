# The public part of the leak check: rules that hold for any package. The
# check against names specific to the vocabulary's source runs only where
# that source is, at build time (data-raw/leak_scan.py), and is not shipped.

leak_public_rules <- data.frame(
  pattern = c("/Users/[A-Za-z]", "/home/[a-z]", "(?i)[A-Z]:\\\\Users\\\\", "~/Projects",
              "(?i)file://",
              paste0("\\b[A-Za-z0-9._%+-]+@(?!example\\.(?:org|com)\\b|philippa\\.page\\b)",
                     "[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}\\b"),
              "(?i)users\\.noreply\\.github\\.com", "git@github-[A-Za-z0-9-]+"),
  why = c("a local macOS path", "a local Linux path", "a local Windows path", "a local path",
          "a local file link", "an e-mail address", "an account's private address",
          "a local SSH host alias")
)

# In the vocabulary only: no hosting namespace, so that no base URI is baked in.
leak_vocab_rules <- data.frame(
  pattern = c("(?i)github\\.io", "(?i)philippa\\.page"),
  why = c("a hosting namespace", "a candidate namespace")
)

leak_hits <- function(text, rules = leak_public_rules, uris = FALSE) {
  text <- paste(as.character(unlist(text)), collapse = "\n")
  text <- gsub("[[:space:]]*\n[[:space:]]*(#'[[:space:]]*)?", " ", text, perl = TRUE)
  hits <- character()
  for (i in seq_len(nrow(rules))) {
    m <- regmatches(text, gregexpr(rules$pattern[i], text, perl = TRUE))[[1]]
    if (length(m)) hits <- c(hits, paste0(m, " (", rules$why[i], ")"))
  }
  if (uris) {
    m <- regmatches(text, gregexpr("[A-Za-z][A-Za-z0-9+.-]*://|\\bwww\\.", text, perl = TRUE))[[1]]
    if (length(m)) hits <- c(hits, paste0(m, " (a URI outside a crosswalk)"))
  }
  unique(hits)
}

# Every string in the vocabulary, with crosswalk links set apart: they are
# the only place a URI may appear.
vocab_strings <- function(x) {
  out <- list(text = character(), uri = character())
  walk <- function(x, key = "", in_map = FALSE) {
    if (is.list(x)) {
      nm <- names(x) %||% rep("", length(x))
      for (i in seq_along(x)) walk(x[[i]], nm[i], in_map || identical(nm[i], "mappings"))
    } else if (is.character(x)) {
      if (in_map && identical(key, "uri")) out$uri <<- c(out$uri, x)
      else out$text <<- c(out$text, x)
    }
  }
  walk(x)
  out
}

`%||%` <- function(a, b) if (is.null(a)) b else a
