#' The default knowledge-layer folder
#'
#' Every function that reads or writes the layer takes a `path` argument
#' defaulting to this. Set it once per session (or in `.Rprofile`) instead
#' of passing `path` to every call:
#' `options(knowledgelayer.path = "S:/Analytics")`.
#'
#' @return The value of `getOption("knowledgelayer.path")`, or `"."`.
#' @export
kl_path <- function() getOption("knowledgelayer.path", ".")

# Files are written and read as UTF-8 bytes, never through the native code
# page: before R 4.2 on Windows that would rewrite characters such as "Ł"
# and make an unaltered decision log look tampered with.
write_utf8 <- function(text, file, append = FALSE) {
  con <- file(file, if (append) "ab" else "wb")
  on.exit(close(con))
  writeBin(charToRaw(enc2utf8(paste(text, collapse = "\n"))), con)
}

read_utf8_lines <- function(file) {
  if (!file.exists(file) || file.size(file) == 0) return(character())
  txt <- rawToChar(readBin(file, "raw", file.size(file)))
  Encoding(txt) <- "UTF-8"
  lines <- strsplit(txt, "\r?\n")[[1]]
  lines[nzchar(lines)]
}

kl_dir <- function(path = kl_path()) {
  d <- file.path(path, "knowledge")
  if (!dir.exists(d)) {
    stop("No knowledge layer at '", normalizePath(path, mustWork = FALSE),
         "'. Run kl_init() first.", call. = FALSE)
  }
  d
}

now_utc <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

read_json_file <- function(file, default) {
  if (!file.exists(file)) return(default)
  jsonlite::read_json(file, simplifyVector = FALSE)
}

write_json_file <- function(x, file) {
  jsonlite::write_json(x, file, auto_unbox = TRUE, pretty = TRUE, null = "null")
  invisible(file)
}

collapse <- function(x) paste(as.character(unlist(x)), collapse = "; ")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

#' Hash a string or a file
#'
#' Uses SHA-256 when the 'openssl' package is installed and MD5 (base R)
#' otherwise. The algorithm is returned with the digest so a log written on
#' one machine can be verified on another. The hash makes tampering
#' detectable; it is not a security control.
#'
#' @param x A character string, or a file path when `file = TRUE`.
#' @param file Treat `x` as a path and hash the file's bytes.
#' @param algo `"sha256"` or `"md5"`. By default, SHA-256 when 'openssl' is
#'   installed and MD5 otherwise.
#' @return A string of the form `"sha256:<hex>"` or `"md5:<hex>"`.
#' @export
kl_hash <- function(x, file = FALSE, algo = NULL) {
  if (is.null(algo)) {
    algo <- if (requireNamespace("openssl", quietly = TRUE)) "sha256" else "md5"
  }
  algo <- match.arg(algo, c("sha256", "md5"))
  if (algo == "sha256") {
    if (!requireNamespace("openssl", quietly = TRUE)) {
      stop("SHA-256 needs the 'openssl' package: install.packages(\"openssl\").",
           call. = FALSE)
    }
    h <- if (file) {
      con <- base::file(x, "rb")
      on.exit(close(con))
      openssl::sha256(con)
    } else {
      openssl::sha256(enc2utf8(x))
    }
    return(paste0("sha256:", as.character(h)))
  }
  f <- if (file) x else {
    tmp <- tempfile()
    on.exit(unlink(tmp))
    writeBin(charToRaw(enc2utf8(x)), tmp)
    tmp
  }
  paste0("md5:", unname(tools::md5sum(f)))
}

`%|na|%` <- function(a, b) if (length(a) == 0 || is.na(a)) b else a
