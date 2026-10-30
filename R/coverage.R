#' The LG Inform Plus capability checklist
#'
#' Thirty-seven rows describing what the UK Local Government Association's
#' LG Inform Plus service offers councils: 22 capabilities (registers, report
#' builders, open-data APIs, benchmarking) and 15 design patterns that recur
#' across them (identifiers in URLs, versioned changelogs, public by
#' default). Cataloged from the service's public guidance and walks of its
#' public pages. Structure only: no LGA dataset is reproduced.
#'
#' The rows use UK local-government terms; [kl_uk_terms()] translates them.
#' To measure your own jurisdiction, start a matrix with [kl_coverage_new()]
#' and follow "Fit it to your city" in the vignette. The method was first
#' worked through in the author's personal DC Inform+ project.
#'
#' @return A data frame with columns `id`, `kind` (`capability` or
#'   `pattern`), `theme`, `capability`, `uk_tool` and `uk_status`
#'   (`confirmed-live`: seen working; `documented-from-guides`: described in
#'   published guidance but not seen working).
#' @source LG Inform Plus programme, Local Government Association
#'   (\url{https://about.esd.org.uk}). The esd standards are reusable under
#'   the Open Government Licence with attribution to the LG Inform Plus
#'   programme.
#' @examples
#' cl <- kl_checklist()
#' table(cl$theme, cl$kind)
#' @export
kl_checklist <- function() {
  file <- system.file("extdata", "lginform_checklist.csv", package = "knowledgelayer")
  cl <- utils::read.csv(file, colClasses = "character", fileEncoding = "UTF-8")
  attr(cl, "attribution") <- paste(
    "Capability structure drawn from the LG Inform Plus programme",
    "(Local Government Association), Open Government Licence.")
  cl
}

#' UK terms in the checklist, translated
#'
#' The checklist describes a UK service in UK local-government language.
#' This table gives each term that appears in it a plain meaning and the
#' nearest US equivalent. Where there is no close equivalent, it says so
#' rather than forcing one: those rows are often the interesting gaps.
#'
#' @return A data frame with columns `term`, `meaning` and `us_nearest`.
#' @examples
#' kl_uk_terms()[, c("term", "us_nearest")]
#' @export
kl_uk_terms <- function() {
  t <- function(term, meaning, us_nearest) data.frame(term = term, meaning = meaning,
                                                      us_nearest = us_nearest)
  rbind(
    t("Council / local authority", "A unit of local government in England.",
      "City or county government."),
    t("LGA (Local Government Association)", "The membership body for councils in England.",
      "National League of Cities; National Association of Counties."),
    t("LG Inform Plus", "The LGA's shared data, standards and benchmarking service for councils.",
      "No single equivalent; closest are state and municipal open-data portals plus peer benchmarking networks."),
    t("esd standards", "Shared lists (services, functions, area types and more) that councils use to describe their work the same way.",
      "No common equivalent; some open-data schemas cover parts."),
    t("ONS (Office for National Statistics)", "The UK's national statistics agency.",
      "U.S. Census Bureau, with other federal statistical agencies."),
    t("GSS code", "The standard identifier for a UK statistical geography.",
      "FIPS code or Census GEOID."),
    t("Postcode", "UK mail code, precise to a handful of addresses.",
      "ZIP code (much larger), or ZIP+4."),
    t("Ward", "A local electoral area within a council.",
      "City ward or council district."),
    t("LSOA / MSOA", "Small census areas (about 1,500 and 7,000 residents).",
      "Census block group and census tract, roughly."),
    t("Statistical neighbors", "A published, documented set of comparable councils for benchmarking.",
      "Peer cities or peer jurisdictions, usually chosen case by case."),
    t("Benchmarking club", "Councils agreeing to collect and share the same data so they can compare.",
      "Multi-city performance consortia; uncommon."),
    t("Statutory / powers and duties register", "A register of what a council must do by law (duties) and may do (powers).",
      "Municipal code and state statutes; rarely kept as a register keyed to services."),
    t("Finance settlement", "Central government's annual funding allocation to councils.",
      "State aid formulas and the annual budget appropriation."),
    t("IAR (information asset register)", "A register of an organization's significant data holdings.",
      "Data inventory or enterprise dataset inventory."),
    t("RoPA (record of processing activities)", "The UK GDPR's required record of how personal data is processed.",
      "No direct equivalent; closest are privacy impact assessments."),
    t("ICO (Information Commissioner's Office)", "The UK's data-protection and freedom-of-information regulator.",
      "No single equivalent; split across state FOIA bodies and privacy regulators."),
    t("Records retention", "Rules for how long each kind of record is kept.",
      "Records retention schedule (same idea)."),
    t("Metric type", "A defined indicator: what is measured, how, and in what units.",
      "Performance measure definition."),
    t("Polarity", "Whether a higher value of a measure is better or worse.",
      "Same idea; often implicit in US dashboards."),
    t("Area type", "A kind of geography, such as ward or census area.",
      "Same idea: ward, tract, police district, community area."),
    t("OGL (Open Government Licence)", "The UK's standard license for reusing public-sector information, with attribution.",
      "Public domain for federal works; city open-data terms of use."),
    t("RTF", "Rich Text Format: a word-processor file any editor opens.", "Same."),
    t("CURIE", "A compact identifier that expands into a full web address.", "Same.")
  )
}

coverage_status <- c("has", "stub", "missing")

#' Start a coverage matrix for your jurisdiction
#'
#' Copies the checklist into a blank matrix. Each row starts unassessed: no
#' tool, no status. That is deliberate. An unassessed row makes no claim,
#' while a row assessed as `missing` is a finding, and the two are never
#' collapsed.
#'
#' @param jurisdiction Name of the place being measured, e.g. `"Example City"`.
#' @param checklist A checklist in the shape of [kl_checklist()]. Add or drop
#'   rows to fit your remit.
#' @return A data frame with the checklist columns plus `local_tool`,
#'   `local_status`, `evidence`, `gap` and `checked`. It keeps the
#'   checklist's license attribution as `attr(, "attribution")`.
#' @examples
#' city <- kl_coverage_new("Example City")
#' @export
kl_coverage_new <- function(jurisdiction, checklist = kl_checklist()) {
  m <- checklist[, intersect(c("id", "kind", "theme", "capability", "uk_tool", "uk_status"),
                             names(checklist))]
  m$local_tool <- NA_character_
  m$local_status <- NA_character_
  m$evidence <- NA_character_
  m$gap <- NA_character_
  m$checked <- NA_character_
  attr(m, "jurisdiction") <- jurisdiction
  # rbind() drops attributes, so a checklist with added rows needs this back.
  attr(m, "attribution") <- attr(checklist, "attribution") %||%
    attr(kl_checklist(), "attribution")
  m
}

#' Assess one row of a coverage matrix
#'
#' @param m A matrix from [kl_coverage_new()].
#' @param id Row id, e.g. `"cap-data-provenance"`.
#' @param tool The local tool that delivers the capability, or `""` if none.
#' @param status `"has"` (works today, publicly), `"stub"` (started or
#'   partial) or `"missing"`.
#' @param evidence Where a reader can verify the status: a URL, a document,
#'   a dated walk. Required for `has` and `stub`.
#' @param gap What is missing, in a sentence.
#' @param checked Date the evidence was checked.
#' @return The updated matrix.
#' @export
kl_coverage_set <- function(m, id, tool = "", status = coverage_status,
                            evidence = "", gap = "", checked = Sys.Date()) {
  status <- match.arg(status)
  i <- match(id, m$id)
  if (is.na(i)) stop("No row with id '", id, "'.", call. = FALSE)
  m$local_tool[i] <- tool
  m$local_status[i] <- status
  m$evidence[i] <- evidence
  m$gap[i] <- gap
  m$checked[i] <- format(as.Date(checked))
  m
}

#' Check a coverage matrix is honest
#'
#' Enforces the rules that keep a matrix defensible: a `has` or `stub` claim
#' must cite evidence, every assessed row must carry the date it was
#' checked, and a `missing` row should say what is missing.
#'
#' @param m A coverage matrix.
#' @return A data frame of problems (`id`, `level`, `problem`), empty when
#'   the matrix passes. `error` rows should block publication; `warning`
#'   rows are worth fixing.
#' @export
kl_coverage_check <- function(m) {
  out <- list()
  add <- function(id, level, problem) {
    out[[length(out) + 1]] <<- data.frame(id = id, level = level, problem = problem)
  }
  blank <- function(x) is.na(x) | !nzchar(trimws(x))
  for (i in seq_len(nrow(m))) {
    s <- m$local_status[i]
    if (is.na(s)) next
    if (!s %in% coverage_status) add(m$id[i], "error", paste0("unknown status '", s, "'"))
    if (s %in% c("has", "stub") && blank(m$evidence[i])) {
      add(m$id[i], "error", paste0("'", s, "' claimed with no evidence"))
    }
    if (blank(m$checked[i])) add(m$id[i], "error", "assessed but no checked date")
    if (s %in% c("stub", "missing") && blank(m$gap[i])) {
      add(m$id[i], "warning", "gap not described")
    }
  }
  if (!length(out)) return(data.frame(id = character(), level = character(), problem = character()))
  do.call(rbind, out)
}

#' Summarize a coverage matrix
#'
#' @param m A coverage matrix.
#' @param by Column to group by, `"theme"` or `"kind"`.
#' @return A table of counts with an `unassessed` column, so progress through
#'   the checklist is visible alongside the findings.
#' @export
kl_coverage_summary <- function(m, by = c("theme", "kind")) {
  by <- match.arg(by)
  s <- ifelse(is.na(m$local_status), "unassessed", m$local_status)
  table(m[[by]], factor(s, levels = c(coverage_status, "unassessed")),
        dnn = c(by, "status"))
}
