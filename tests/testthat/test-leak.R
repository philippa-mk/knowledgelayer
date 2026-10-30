test_that("the leak check catches what it is meant to", {
  expect_true(length(leak_hits("saved under /Users/someone/Projects")) > 0)
  expect_true(length(leak_hits("C:\\Users\\someone\\Documents")) > 0)
  expect_true(length(leak_hits("see file:///tmp/x")) > 0)
  expect_true(length(leak_hits("a link https://example.org in a label", uris = TRUE)) > 0)
  expect_length(leak_hits("a link https://example.org in a label"), 0)
  expect_length(leak_hits("Example City Department of Streets"), 0)
  expect_true(length(leak_hits("write to someone@agency.gov")) > 0)
  expect_true(length(leak_hits("12345+someone@users.noreply.github.com")) > 0)
  expect_true(length(leak_hits("git@github-work:someone/repo.git")) > 0)
  expect_length(leak_hits("analyst.a@example.org, or the maintainer at hello@philippa.page"), 0)
  vocab_rules <- rbind(leak_public_rules, leak_vocab_rules)
  expect_true(length(leak_hits("https://someone.github.io/vocab/x", rules = vocab_rules)) > 0)
  # Extra rules plug in the same way the build-time check adds its own:
  # here an invented city and its invented police department.
  planted <- rbind(leak_public_rules,
                   data.frame(pattern = c("\\bZenithville\\b", "\\bZPD\\b"),
                              why = c("an invented city", "an invented agency")))
  expect_length(leak_hits("records from the ZPD in Zenithville", rules = planted), 2)
  expect_length(leak_hits("records from the police", rules = planted), 0)
})

test_that("the shipped vocabulary passes the leak scan, with URIs only in crosswalks", {
  v <- jsonlite::read_json(system.file("extdata", "vocabulary.json", package = "knowledgelayer"),
                           simplifyVector = FALSE)
  s <- vocab_strings(v)
  vocab_rules <- rbind(leak_public_rules, leak_vocab_rules)
  hits <- unlist(lapply(unique(s$text), leak_hits, rules = vocab_rules, uris = TRUE))
  expect_equal(hits, character())
  # Crosswalk links are web addresses, nothing local, and no hosting namespace.
  expect_true(all(grepl("^https?://", s$uri)))
  expect_equal(unlist(lapply(unique(s$uri), leak_hits, rules = vocab_rules)), character())
  # Ruling 1: concepts are named by short ids.
  ids <- vapply(v$concepts, function(k) k$id, character(1))
  expect_true(all(grepl("^[a-z_]+:[A-Za-z0-9][A-Za-z0-9._-]*$", ids)))
})

test_that("the installed package's files and code pass the leak scan", {
  root <- system.file(package = "knowledgelayer")
  files <- list.files(root, recursive = TRUE, full.names = TRUE)
  files <- files[grepl("\\.(html|Rmd|R|md|json|csv|txt)$|/DESCRIPTION$", files)]
  for (f in files) {
    text <- readLines(f, warn = FALSE, encoding = "UTF-8")
    # R CMD build stamps the builder's account into Packaged:; that is the
    # build machine's, not the package's, and is checked at release.
    if (basename(f) == "DESCRIPTION") text <- text[!grepl("^Packaged:", text)]
    expect_equal(leak_hits(text), character(), label = basename(f))
  }
  ns <- asNamespace("knowledgelayer")
  code <- unlist(lapply(ls(ns, all.names = TRUE), function(n) {
    x <- get(n, envir = ns)
    if (is.function(x)) deparse(x) else character()
  }))
  expect_equal(leak_hits(code), character())
})

test_that("stored tags hold short ids and never a URI", {
  root <- tempfile("kl-")
  kl_init(root)
  kl_add_project("p1", "Contracting review", owner = "A", concepts = "contracting", path = root)
  kl_tag("project", "p1", c("ft:improper-payments", "segregation of duties"), path = root)
  expect_error(kl_tag("project", "p1", "https://example.org/vocab/ft/noncompliance", path = root),
               "no concept")
  stored <- c(readLines(file.path(root, "knowledge", "tags.json")),
              readLines(file.path(root, "knowledge", "projects.json")))
  expect_false(any(grepl("://", stored, fixed = TRUE)))
  expect_setequal(kl_tags(path = root)$concept, c("ft:improper-payments", "ft:segregation-of-duties"))
})
