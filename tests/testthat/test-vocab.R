new_layer <- function() {
  root <- tempfile("kl-")
  kl_init(root)
  root
}

copy_v01 <- function() {
  root <- tempfile("kl-v01-")
  dir.create(root)
  file.copy(list.files(test_path("fixtures", "v0.1-layer"), full.names = TRUE), root,
            recursive = TRUE)
  dir.create(file.path(root, "knowledge", "handoffs"), showWarnings = FALSE)
  root
}

test_that("the shipped vocabulary has its schemes, its provenance and a clean check", {
  v <- kl_vocab(path = tempdir())
  expect_setequal(unique(v$scheme), c("oversight_concepts", "report_types", "criteria_types",
                                      "findings_typology", "program_areas"))
  expect_true(all(v$source == "shipped"))
  src <- attr(v, "source")
  expect_equal(src$sha256, "3ad05b0a5ba066fe662b73fc1629d8429bed4af3efcc796811cde82de08f994e")
  expect_equal(src$version, "0.18.1")
  expect_equal(nrow(kl_vocab("findings_typology", path = tempdir())), 17)
  chk <- kl_vocab_check(tempdir())
  expect_false(any(chk$level == "error"))
  expect_output(print(chk), "PASS WITH WARNINGS")
})

test_that("kl_resolve matches through synonyms and never guesses", {
  r <- kl_resolve(c("Segregation of Duties", "  separation   of duties ", "ft:noncompliance",
                    "embezzlement", "segregation", "parking tickets"), path = tempdir())
  expect_equal(r$status, c("match", "match", "match", "ambiguous", "no concept", "no concept"))
  expect_equal(r$id[1:3], c("ft:segregation-of-duties", "ft:segregation-of-duties",
                            "ft:noncompliance"))
  expect_true(is.na(r$id[4]))
  expect_match(r$candidates[4], "concept:fraud")
  expect_match(r$candidates[4], "ft:fraud-misappropriation")
  # A partial term is not a match, however close.
  expect_true(is.na(r$id[5]))
  # Ambiguity is settled by the caller, with scheme =, never by the function.
  expect_equal(kl_resolve("embezzlement", scheme = "findings_typology", path = tempdir())$id,
               "ft:fraud-misappropriation")
  expect_equal(nrow(kl_resolve(character(), path = tempdir())), 0)
})

test_that("local terms layer over the shipped set and never edit it", {
  root <- new_layer()
  shipped <- system.file("extdata", "vocabulary.json", package = "knowledgelayer")
  before <- kl_hash(shipped, file = TRUE, algo = "md5")
  kl_vocab_extend("agencies", "agency:streets", "Department of Streets",
                  altLabels = c("DoS", "Streets"), path = root)
  kl_vocab_extend("program_areas", "area:snow", "Snow Removal", altLabels = "plowing",
                  broader = "cluster:infrastructure", path = root)
  expect_equal(kl_hash(shipped, file = TRUE, algo = "md5"), before)
  expect_true(file.exists(file.path(root, "knowledge", "vocabulary.json")))
  v <- kl_vocab(path = root)
  expect_equal(v$source[v$id == "agency:streets"], "local")
  expect_match(v$narrower[v$id == "cluster:infrastructure"], "area:snow")
  expect_equal(kl_resolve("plowing", path = root)$id, "area:snow")
  # Another folder's layer does not see these terms.
  expect_equal(kl_resolve("plowing", path = new_layer())$status, "no concept")
  # The shipped set cannot be redefined locally.
  expect_error(kl_vocab_extend("findings_typology", "ft:noncompliance", "Something else",
                               path = root), "never edited")
  expect_error(kl_vocab_extend("program_areas", "area:x", "X", broader = "cluster:nowhere",
                               path = root), "not in the vocabulary")
  expect_error(kl_vocab_extend("program_areas", "https://example.org/x", "X", path = root),
               "short id")
  # Updating a local term replaces it.
  kl_vocab_extend("agencies", "agency:streets", "Streets Department", path = root)
  v <- kl_vocab(path = root)
  expect_equal(v$prefLabel[v$id == "agency:streets"], "Streets Department")
  expect_equal(sum(v$id == "agency:streets"), 1)
})

test_that("kl_vocab_import loads program areas and validates every broader first", {
  root <- new_layer()
  csv <- tempfile(fileext = ".csv")
  writeLines(c("id,prefLabel,altLabels,broader",
               "area:transit,Transit Operations,bus; rail,cluster:infrastructure",
               "area:paratransit,Paratransit,dial-a-ride,area:transit",
               "area:libraries,Library Services,,cluster:education"), csv)
  chk <- kl_vocab_import(csv, path = root)
  expect_s3_class(chk, "kl_vocab_check")
  expect_false(any(chk$level == "error"))
  v <- kl_vocab("program_areas", path = root)
  expect_true(all(c("area:transit", "area:paratransit", "area:libraries") %in% v$id))
  expect_equal(v$altLabels[v$id == "area:transit"], "bus; rail")
  expect_equal(kl_resolve("dial-a-ride", path = root)$id, "area:paratransit")

  bad <- tempfile(fileext = ".csv")
  writeLines(c("id,prefLabel,altLabels,broader",
               "area:parks,Parks,,cluster:infrastructure",
               "area:pools,Pools,,cluster:nowhere"), bad)
  expect_error(kl_vocab_import(bad, path = root), "cluster:nowhere")
  # Nothing from the failed file was imported, not even its good row.
  expect_false("area:parks" %in% kl_vocab(path = root)$id)

  nob <- tempfile(fileext = ".csv")
  writeLines(c("id,prefLabel,altLabels,broader", "area:loose,Loose,,"), nob)
  expect_error(kl_vocab_import(nob, path = root), "under a cluster")
  nocol <- tempfile(fileext = ".csv")
  writeLines(c("id,prefLabel", "area:a,A"), nocol)
  expect_error(kl_vocab_import(nocol, path = root), "missing: altLabels, broader")
})

test_that("kl_vocab_check finds dangling ids, cycles and duplicate labels", {
  root <- new_layer()
  kl_vocab_extend("program_areas", "area:a", "Area A", broader = "cluster:health", path = root)
  kl_vocab_extend("program_areas", "area:b", "Area B", altLabels = "Area A",
                  broader = "area:a", path = root)
  lv <- jsonlite::read_json(file.path(root, "knowledge", "vocabulary.json"), simplifyVector = FALSE)
  # Hand edits can introduce what the functions refuse.
  lv$concepts[[1]]$broader <- list("area:b")
  lv$concepts[[2]]$related <- list("area:gone")
  jsonlite::write_json(lv, file.path(root, "knowledge", "vocabulary.json"), auto_unbox = TRUE)
  chk <- kl_vocab_check(root)
  expect_output(print(chk), "FAIL")
  p <- paste(chk$problem, collapse = "\n")
  expect_match(p, "related id 'area:gone' is not in the vocabulary")
  expect_match(p, "cycle")
  expect_match(p, "label 'area a' is on more than one concept in the same scheme")
})

test_that("tags, concepts on projects and typology on findings resolve or refuse", {
  root <- new_layer()
  kl_add_project("p1", "Vendor payments review", owner = "A",
                 concepts = c("contracting", "duplicate payment"), path = root)
  expect_equal(kl_projects(root)$concepts, "concept:procurement; ft:improper-payments")
  expect_error(kl_add_project("p2", "X", owner = "A", concepts = "embezzlement", path = root),
               "ambiguous")
  expect_error(kl_add_project("p2", "X", owner = "A", concepts = "parking tickets", path = root),
               "no concept")
  expect_false("p2" %in% kl_projects(root)$id)
  expect_error(kl_tag("project", "nope", "fraud", path = root), "Not registered")
  kl_log_decision("Scope", "approved", by = "A", path = root)
  kl_tag("decision", 1, "concept:governance", path = root)
  kl_tag("finding", "F1", "ft:noncompliance", path = root)
  kl_tag("finding", "F1", "ft:noncompliance", path = root)
  t <- kl_tags(path = root)
  expect_equal(nrow(t), 2)
  expect_equal(kl_tags("decision", path = root)$prefLabel, "Governance")
  expect_error(kl_tag("decision", 9, "concept:governance", path = root), "No decision")

  f <- kl_findings(c("F1", "F2", "F3"), c("a", "b", "c"), c("high", "low", "med"),
                   c("x", "y", "z"), typology = c("separation of duties", "", "ft:noncompliance"),
                   path = root)
  expect_equal(f$typology, c("ft:segregation-of-duties", "", "ft:noncompliance"))
  # Typology resolves within the findings typology only.
  expect_error(kl_findings("F1", "a", "high", "x", typology = "governance", path = root),
               "no concept")
  file <- tempfile(fileext = ".csv")
  kl_write_findings(f, file)
  expect_equal(kl_read_findings(file, path = root), f)
})

test_that("kl_find searches through synonyms and tags, and whole words only", {
  root <- new_layer()
  kl_add_project("p1", "Vendor contracts and purchasing", owner = "A", path = root)
  kl_add_project("p2", "Public library hours", owner = "B", path = root)
  kl_add_project("p3", "Grants", owner = "C", path = root)
  kl_tag("project", "p3", "concept:procurement", path = root)
  expect_setequal(kl_find("contracting", root)$id, c("p1", "p3"))
  expect_equal(kl_find("library", root)$id, "p2")
  # "IC" is a synonym of internal controls; it must not match "public".
  kl_add_project("p4", "Controls testing", owner = "D", path = root)
  expect_equal(kl_find("internal controls", root)$id, "p4")
})

test_that("kl_link accepts the SKOS relations", {
  root <- new_layer()
  kl_add_project("a", "A", owner = "X", path = root)
  kl_add_project("b", "B", owner = "X", path = root)
  for (r in c("broader", "narrower", "related")) kl_link("a", "b", r, path = root)
  expect_setequal(kl_links(root)$relation, c("broader", "narrower", "related"))
  expect_error(kl_link("a", "b", "sameAs", path = root))
})

test_that("v0.1 files load unchanged and migrate to kl-projects/2 on the next write", {
  root <- copy_v01()
  pj <- file.path(root, "knowledge", "projects.json")
  before <- readLines(pj)
  p <- kl_projects(root)
  expect_equal(p$id, c("intake-2025", "contracts-2026"))
  expect_equal(p$concepts, c("", ""))
  expect_equal(readLines(pj), before)
  expect_equal(nrow(kl_links(root)), 1)
  expect_silent(suppressMessages(kl_verify_log(root)))
  expect_equal(kl_single_points(path = root)$id, "intake-2025")
  kl_add_project("new-2026", "New", owner = "A", concepts = "fraud waste and abuse", path = root)
  reg <- jsonlite::read_json(pj)
  expect_equal(reg$schema, "kl-projects/2")
  expect_equal(length(reg$projects), 3)
  expect_equal(reg$projects[[1]]$registered, jsonlite::read_json(
    test_path("fixtures", "v0.1-layer", "knowledge", "projects.json"))$projects[[1]]$registered)
  expect_equal(reg$projects[[1]]$concepts, list())
  expect_equal(kl_projects(root)$concepts[3], "concept:fraud-waste-abuse")
  # A file from a newer version is refused, not misread.
  reg$schema <- "kl-projects/3"
  jsonlite::write_json(reg, pj, auto_unbox = TRUE)
  expect_error(kl_projects(root), "cannot read")
})

test_that("a v0.1 set of findings keeps its fingerprint", {
  f <- kl_read_findings(test_path("fixtures", "v0.1-layer", "findings.csv"), path = tempdir())
  expect_equal(findings_hash(f, algo = "md5"), "md5:0415998a443f0cf745432eedf89ea765")
  skip_if_not_installed("openssl")
  expect_equal(findings_hash(f, algo = "sha256"),
               "sha256:3e713d13e84a97f3c3af1dd780ca4ace17ba419b8759102375744092ba54eb55")
})

test_that("crosswalk precision is said plainly, and only exact links are offered as exact", {
  expect_equal(precision_label(c("principle", "item", "section")),
               c("direct link to this principle", "direct link to this item",
                 "direct link to this section"))
  for (p in c("scheme", "search", "unknown", "")) {
    expect_match(precision_label(p), "not to this point")
  }
  cw <- kl_crosswalks("ft:internal-control-weakness", path = tempdir())
  gb <- cw[cw$scheme == "GAO-Green-Book", ]
  expect_equal(gb$precision, "scheme")
  expect_equal(gb$precision_label, "link to the whole standard, not to this point")
  expect_match(gb$label, "GAO-25-107721")
})

test_that("the review page shows each finding's kind and labeled crosswalks", {
  root <- new_layer()
  f <- kl_findings(c("F1", "F2"), c("Same clerk approves and pays", "Typo"), c("high", "low"),
                   c("Split the duties", "Fix it"),
                   typology = c("ft:internal-control-weakness", ""), path = root)
  page <- tempfile(fileext = ".html")
  kl_review_page(f, page, "qa-1", path = root)
  html <- paste(readLines(page, encoding = "UTF-8"), collapse = "\n")
  expect_match(html, "Internal Control Weakness", fixed = TRUE)
  expect_match(html, "link to the whole standard, not to this point", fixed = TRUE)
  expect_match(html, "Kind of finding", fixed = TRUE)
  # A finding with no typology adds nothing.
  f0 <- kl_findings("F1", "Typo", "low", "Fix it")
  kl_review_page(f0, page, "qa-2", path = root)
  expect_match(paste(readLines(page), collapse = "\n"), '"vocab":{}', fixed = TRUE)
})

test_that("kl_export_skos needs a base, and writes it nowhere else", {
  root <- new_layer()
  out <- tempfile(fileext = ".ttl")
  expect_error(kl_export_skos(out, path = root), "needs `base`")
  expect_error(kl_export_skos(out, base = "", path = root), "needs `base`")
  expect_error(kl_export_skos(out, base = "data.example.org/vocab/", path = root), "needs `base`")
  expect_error(kl_export_skos(out, base = "https://data.example.org/vocab", path = root),
               "ending in / or #")
  expect_false(file.exists(out))
  kl_add_project("p1", "Vendor \"payments\" review", owner = "A", concepts = "contracting",
                 path = root)
  kl_vocab_extend("program_areas", "area:snow", "Snow Removal", broader = "cluster:infrastructure",
                  path = root)
  kl_export_skos(out, base = "https://data.example.org/vocab/", projects = TRUE, path = root)
  ttl <- readLines(out, encoding = "UTF-8")
  expect_true(any(ttl == "<https://data.example.org/vocab/ft/noncompliance> a skos:Concept ;"))
  expect_true(any(grepl("area/snow> a skos:Concept", ttl, fixed = TRUE)))
  expect_true(any(grepl('dct:title "Vendor \\"payments\\" review"@en', ttl, fixed = TRUE)))
  expect_true(any(grepl("dct:subject <https://data.example.org/vocab/concept/procurement>", ttl,
                        fixed = TRUE)))
  # A whole-standard crosswalk is seeAlso, never a SKOS match.
  i <- which(ttl == "<https://data.example.org/vocab/ft/internal-control-weakness> a skos:Concept ;")
  block <- ttl[i:(i + which(ttl[i:length(ttl)] == "")[1] - 1)]
  expect_true(any(grepl("rdfs:seeAlso <https://www.gao.gov/greenbook>", block, fixed = TRUE)))
  # Every concept IRI is under the base supplied; nothing else is invented.
  iris <- unlist(regmatches(ttl, gregexpr("<[^>]+>", ttl)))
  ours <- iris[!grepl("^<http://(www\\.w3\\.org|purl\\.org)/", iris)]
  shipped_links <- unlist(lapply(jsonlite::read_json(system.file("extdata", "vocabulary.json",
    package = "knowledgelayer"))$concepts, function(k) vapply(k$mappings, function(m) m$uri, "")))
  expect_true(all(startsWith(ours, "<https://data.example.org/vocab/") |
                    gsub("[<>]", "", ours) %in% shipped_links))
})

test_that("the shipped vocabulary carries her program-areas verdicts and rulings", {
  v <- kl_vocab(path = tempdir())
  expect_equal(as.list(table(v$scheme)),
               list(criteria_types = 6L, findings_typology = 17L, oversight_concepts = 47L,
                    program_areas = 63L, report_types = 11L))
  raw <- jsonlite::read_json(system.file("extdata", "vocabulary.json", package = "knowledgelayer"))
  expect_null(raw$placeholder)
  expect_equal(raw$program_areas_review$sha256,
               "262811d3e1f905c8a579eb62c48b5cee1140adf2e07d4e3488afa614dab0b77f")
  expect_equal(raw$program_areas_review$middle_level, 54L)
  expect_equal(v$prefLabel[v$id == "cluster:human-services"], "Human Services")
  expect_equal(v$prefLabel[v$id == "cluster:education"], "Education")
})

test_that("every shipped crosswalk is verified, with a stated precision", {
  ks <- jsonlite::read_json(system.file("extdata", "vocabulary.json", package = "knowledgelayer"))$concepts
  ms <- unlist(lapply(ks, function(k) k$mappings), recursive = FALSE)
  expect_gt(length(ms), 0)
  for (m in ms) {
    expect_true(m$precision %in% c("item", "principle", "section", "scheme", "search"), label = m$uri)
    expect_match(m$verified, "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", label = m$uri)
    expect_false(grepl("verify", m$label, ignore.case = TRUE), label = m$label)
  }
})

test_that("the local edits for her four review notes are in place", {
  v <- kl_vocab(path = tempdir())
  get <- function(id, col) v[[col]][v$id == id]
  # 1. Human services is not human resources.
  expect_match(get("cluster:human-services", "scopeNote"), "Not human resources")
  expect_false(grepl("human resources|personnel|\\bHR\\b", get("cluster:human-services", "altLabels"),
                     ignore.case = TRUE))
  expect_equal(kl_resolve(c("human resources", "human services"), path = tempdir())$id,
               c("concept:personnel-hr", "cluster:human-services"))
  # 2. Public health resolves cleanly, through its synonyms too.
  expect_equal(kl_resolve(c("public health", "disease prevention", "population health"),
                          path = tempdir())$id, rep("concept:public-health", 3))
  root <- new_layer()
  kl_add_project("flu", "Flu shot clinic audit", owner = "A", concepts = "public health", path = root)
  expect_equal(kl_find("health promotion", root)$id, "flu")
  # 3. Lead poisoning stays under health, related to public health and water.
  expect_equal(get("concept:lead-poisoning", "broader"), "cluster:health")
  expect_match(get("concept:lead-poisoning", "related"), "concept:public-health")
  expect_match(get("concept:lead-poisoning", "related"), "concept:water-quality")
  expect_match(get("concept:water-quality", "related"), "concept:lead-poisoning")
  # 4. DD is spelled out, and "DD waiver" names the waiver alone.
  expect_match(get("concept:dd-waiver", "prefLabel"), "Developmental Disabilities")
  expect_match(get("concept:dd-waiver", "scopeNote"), "DD stands for developmental disabilities")
  expect_equal(kl_resolve("DD waiver", path = tempdir())$id, "concept:dd-waiver")
  edits <- jsonlite::read_json(system.file("extdata", "vocabulary.json",
                                           package = "knowledgelayer"))$local_edits
  expect_setequal(vapply(edits, function(e) e$id, ""),
                  c("cluster:human-services", "concept:personnel-hr", "concept:public-health",
                    "concept:lead-poisoning", "concept:dd-waiver", "concept:developmental-disabilities",
                    "concept:executive-management-of-agencies", "concept:checks-and-balances",
                    "concept:oversight-independence"))
})

test_that("terms resolve by context: a finding's kind from the findings typology only", {
  # On its own, "improper payment" is both a kind of finding and a program area.
  r <- kl_resolve("improper payment", path = tempdir())
  expect_equal(r$status, "ambiguous")
  expect_match(r$candidates, "ft:improper-payments")
  expect_match(r$candidates, "concept:benefit-overpayment")
  # In a finding's context it can only be the kind of finding.
  f <- kl_findings("F1", "Paid twice", "high", "Recover it", typology = "improper payment",
                   path = tempdir())
  expect_equal(f$typology, "ft:improper-payments")
  root <- new_layer()
  kl_tag("finding", "F1", "improper payment", path = root)
  expect_equal(kl_tags("finding", path = root)$concept, "ft:improper-payments")
  # A project has no such context, so the term still needs narrowing there.
  kl_add_project("p1", "Benefits review", owner = "A", path = root)
  expect_error(kl_tag("project", "p1", "improper payment", path = root), "ambiguous")
  kl_tag("project", "p1", "improper payment", scheme = "program_areas", path = root)
  expect_equal(kl_tags("project", path = root)$concept, "concept:benefit-overpayment")
})

test_that("crosswalks to a whole document never claim to point at one item", {
  cw <- function(id) kl_crosswalks(id, path = tempdir())
  ip <- cw("ft:improper-payments")
  expect_setequal(ip$scheme, c("PIIA", "OMB-A-123-C"))
  expect_true(all(ip$precision == "scheme"))
  # One document per crosswalk: the act and the OMB appendix are separate.
  expect_false(any(grepl("A-123", ip$label[ip$scheme == "PIIA"])))
  expect_equal(cw("ft:eligibility-error")$precision, "scheme")
  fm <- cw("ft:fraud-misappropriation")
  expect_equal(fm$precision[fm$scheme == "ACFE"], "scheme")
})

test_that("three public-administration concepts carry exactly their neutral wording", {
  v <- kl_vocab(path = tempdir())
  alt <- function(id) strsplit(v$altLabels[v$id == id], "; ", fixed = TRUE)[[1]]
  expect_equal(v$prefLabel[v$id == "concept:checks-and-balances"], "Checks and Balances")
  expect_setequal(alt("concept:checks-and-balances"),
                  c("separation of powers", "institutional safeguards", "democratic governance",
                    "rule of law", "institutional resilience"))
  expect_equal(v$prefLabel[v$id == "concept:executive-management-of-agencies"],
               "Executive Management of Agencies")
  expect_setequal(alt("concept:executive-management-of-agencies"),
                  c("executive control of agencies", "agency reorganization",
                    "political appointments", "executive orders and directives"))
  expect_equal(v$prefLabel[v$id == "concept:oversight-independence"],
               "Independence of Oversight Offices")
  expect_setequal(alt("concept:oversight-independence"),
                  c("IG independence", "auditor independence", "organizational independence",
                    "oversight capacity", "inspector general capacity"))
})
