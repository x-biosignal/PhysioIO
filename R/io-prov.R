# Provenance serialization to and from the W3C PROV interchange formats
# (PROV-JSON, PROV JSON-LD, PROV-N). The PhysioExperiment provenance table
# (see PhysioCore::provenance) is mapped onto a PROV document: each recorded
# activity becomes a prov:Activity, its generated entity a prov:Entity, its
# agent a prov:Agent, and the used/generated/association edges the corresponding
# PROV relations. Every column is also carried verbatim as a physio: attribute
# so that a writeProv() -> readProv() round-trip reproduces the table exactly.

.PROV_NS  <- "https://x-biosignal.org/physio-prov#"
.PROVO_NS <- "http://www.w3.org/ns/prov#"
.FOAF_NS  <- "http://xmlns.com/foaf/0.1/"

# ordered string columns carried losslessly as physio: attributes
.PROV_STR_COLS <- c("step", "activity", "entity", "used", "generated",
                    "agent", "user", "package", "version", "params", "params_json")
.PROV_EPOCH_COLS <- c("startedAtTime", "endedAtTime", "timestamp")

.emptyObj <- function() structure(list(), names = character(0))

.provIso <- function(t) {
  if (length(t) == 0L || is.na(t)) return(NA_character_)
  format(as.POSIXct(t, origin = "1970-01-01"), "%Y-%m-%dT%H:%M:%OS3")
}

# one activity attribute object carrying the full row (lossless)
.provRowAttrs <- function(prov, i) {
  attrs <- list(
    "prov:startTime" = .provIso(prov$startedAtTime[i]),
    "prov:endTime"   = .provIso(prov$endedAtTime[i]),
    "physio:index"   = i
  )
  for (col in .PROV_STR_COLS) {
    v <- prov[[col]][i]
    attrs[[paste0("physio:", col)]] <- if (is.na(v)) NULL else as.character(v)
  }
  for (col in .PROV_EPOCH_COLS) {
    v <- as.numeric(prov[[col]][i])
    attrs[[paste0("physio:", col, "Epoch")]] <- if (is.na(v)) NULL else v
  }
  attrs
}

# ---- PROV-JSON --------------------------------------------------------------

.toProvJson <- function(prov) {
  doc <- list(prefix = list(physio = .PROV_NS, prov = .PROVO_NS, foaf = .FOAF_NS))
  n <- nrow(prov)
  entity <- .emptyObj(); activity <- .emptyObj(); agent <- .emptyObj()
  wgb <- .emptyObj(); used <- .emptyObj(); waw <- .emptyObj()
  for (i in seq_len(n)) {
    aId <- paste0("physio:activity", i)
    eId <- paste0("physio:entity", i)
    gId <- paste0("physio:agent", i)
    activity[[aId]] <- .provRowAttrs(prov, i)
    entity[[eId]] <- list("physio:id" = as.character(prov$entity[i] %||% eId))
    agent[[gId]] <- list("prov:type" = "prov:SoftwareAgent",
                         "foaf:name" = as.character(prov$agent[i] %||% NA_character_))
    wgb[[paste0("_:wgb", i)]] <- list("prov:entity" = eId, "prov:activity" = aId,
                                      "prov:time" = .provIso(prov$endedAtTime[i]))
    inp <- prov$used[i]
    if (!is.na(inp) && nzchar(inp)) {
      used[[paste0("_:u", i)]] <- list("prov:activity" = aId,
                                       "prov:entity" = paste0("physio:assay_", inp),
                                       "prov:time" = .provIso(prov$startedAtTime[i]))
    }
    waw[[paste0("_:assoc", i)]] <- list("prov:activity" = aId, "prov:agent" = gId)
  }
  doc$entity <- entity; doc$activity <- activity; doc$agent <- agent
  doc$wasGeneratedBy <- wgb; doc$used <- used; doc$wasAssociatedWith <- waw
  doc
}

.provJsonToDf <- function(doc) {
  acts <- doc$activity
  if (is.null(acts) || length(acts) == 0L) return(.emptyProvDf())
  idx <- vapply(acts, function(a) as.integer(a[["physio:index"]] %||% NA), integer(1))
  acts <- acts[order(idx)]
  getc <- function(col) vapply(acts, function(a)
    as.character(a[[paste0("physio:", col)]] %||% NA_character_), character(1))
  gett <- function(col) as.POSIXct(vapply(acts, function(a)
    as.numeric(a[[paste0("physio:", col, "Epoch")]] %||% NA), numeric(1)),
    origin = "1970-01-01", tz = "")
  .assembleProvDf(getc, gett)
}

# ---- PROV JSON-LD -----------------------------------------------------------

.toProvJsonLd <- function(prov) {
  ctx <- list(physio = .PROV_NS, prov = .PROVO_NS, foaf = .FOAF_NS)
  graph <- list()
  for (i in seq_len(nrow(prov))) {
    node <- c(list("@id" = paste0("physio:activity", i), "@type" = "prov:Activity"),
              .provRowAttrs(prov, i))
    graph[[length(graph) + 1L]] <- node
  }
  list("@context" = ctx, "@graph" = graph)
}

.provJsonLdToDf <- function(doc) {
  graph <- doc[["@graph"]]
  acts <- Filter(function(nd) identical(nd[["@type"]], "prov:Activity"), graph)
  if (length(acts) == 0L) return(.emptyProvDf())
  idx <- vapply(acts, function(a) as.integer(a[["physio:index"]] %||% NA), integer(1))
  acts <- acts[order(idx)]
  getc <- function(col) vapply(acts, function(a)
    as.character(a[[paste0("physio:", col)]] %||% NA_character_), character(1))
  gett <- function(col) as.POSIXct(vapply(acts, function(a)
    as.numeric(a[[paste0("physio:", col, "Epoch")]] %||% NA), numeric(1)),
    origin = "1970-01-01", tz = "")
  .assembleProvDf(getc, gett)
}

# ---- PROV-N -----------------------------------------------------------------

.toProvN <- function(prov) {
  lines <- c("document",
             sprintf("  prefix physio <%s>", .PROV_NS),
             sprintf("  prefix prov <%s>", .PROVO_NS),
             sprintf("  prefix foaf <%s>", .FOAF_NS))
  for (i in seq_len(nrow(prov))) {
    aId <- paste0("physio:activity", i)
    # full row carried as a base64 attribute for a lossless round-trip
    blob <- jsonlite::base64_enc(charToRaw(
      jsonlite::toJSON(.provRowAttrs(prov, i), auto_unbox = TRUE, null = "null")))
    st <- .provIso(prov$startedAtTime[i]); en <- .provIso(prov$endedAtTime[i])
    st <- if (is.na(st)) "-" else st; en <- if (is.na(en)) "-" else en
    name <- as.character(prov$activity[i] %||% prov$step[i] %||% "")
    lines <- c(lines,
      sprintf("  entity(physio:entity%d)", i),
      sprintf("  agent(physio:agent%d, [prov:type='prov:SoftwareAgent'])", i),
      sprintf("  activity(%s, %s, %s, [physio:name=\"%s\", physio:data=\"%s\"])",
              aId, st, en, name, blob),
      sprintf("  wasGeneratedBy(physio:entity%d, %s, -)", i, aId),
      sprintf("  wasAssociatedWith(%s, physio:agent%d, -)", aId, i))
  }
  paste(c(lines, "endDocument", ""), collapse = "\n")
}

.provNToDf <- function(txt) {
  blobs <- regmatches(txt, gregexpr('physio:data="([^"]*)"', txt))[[1]]
  if (length(blobs) == 0L) return(.emptyProvDf())
  b64 <- sub('physio:data="([^"]*)"', "\\1", blobs)
  recs <- lapply(b64, function(b)
    jsonlite::fromJSON(rawToChar(jsonlite::base64_dec(b)), simplifyVector = FALSE))
  idx <- vapply(recs, function(a) as.integer(a[["physio:index"]] %||% NA), integer(1))
  recs <- recs[order(idx)]
  getc <- function(col) vapply(recs, function(a)
    as.character(a[[paste0("physio:", col)]] %||% NA_character_), character(1))
  gett <- function(col) as.POSIXct(vapply(recs, function(a)
    as.numeric(a[[paste0("physio:", col, "Epoch")]] %||% NA), numeric(1)),
    origin = "1970-01-01", tz = "")
  .assembleProvDf(getc, gett)
}

# ---- shared data.frame (re)assembly -----------------------------------------

.emptyProvDf <- function() {
  data.frame(step = character(0), activity = character(0), entity = character(0),
             used = character(0), generated = character(0), agent = character(0),
             user = character(0), package = character(0), version = character(0),
             startedAtTime = as.POSIXct(character(0)),
             endedAtTime = as.POSIXct(character(0)),
             timestamp = as.POSIXct(character(0)),
             params = character(0), params_json = character(0),
             stringsAsFactors = FALSE)
}

.assembleProvDf <- function(getc, gett) {
  out <- data.frame(
    step = unname(getc("step")), activity = unname(getc("activity")),
    entity = unname(getc("entity")), used = unname(getc("used")),
    generated = unname(getc("generated")), agent = unname(getc("agent")),
    user = unname(getc("user")), package = unname(getc("package")),
    version = unname(getc("version")),
    startedAtTime = gett("startedAtTime"), endedAtTime = gett("endedAtTime"),
    timestamp = gett("timestamp"),
    params = unname(getc("params")), params_json = unname(getc("params_json")),
    stringsAsFactors = FALSE
  )
  rownames(out) <- NULL
  out
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L || (length(a) == 1L && is.na(a))) b else a

# ---- public API -------------------------------------------------------------

#' Serialize a provenance trail to a W3C PROV interchange file
#'
#' Writes the provenance / audit trail of a \code{PhysioExperiment} (or a
#' provenance \code{data.frame} from \code{\link[PhysioCore]{provenance}}) to a
#' W3C PROV document. Three interchange syntaxes are supported: PROV-JSON
#' (default), PROV in JSON-LD, and PROV-N. The document round-trips exactly
#' through \code{\link{readProv}}.
#'
#' @param x A \code{PhysioExperiment} or a provenance \code{data.frame}.
#' @param path Output file path.
#' @param format One of \code{"prov-json"}, \code{"json-ld"}, \code{"prov-n"}.
#' @return \code{path}, invisibly.
#' @references W3C PROV-JSON (Huynh et al. 2013); PROV-O; PROV-N.
#' @seealso \code{\link{readProv}}, \code{\link[PhysioCore]{provenance}}
#' @examples
#' pe <- PhysioExperiment(
#'   S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)), samplingRate = 100)
#' pe <- logStep(pe, "filterSignals", params = list(low = 1, high = 40))
#' tf <- tempfile(fileext = ".json")
#' writeProv(pe, tf)
#' readProv(tf)$activity
#' @export
writeProv <- function(x, path, format = c("prov-json", "json-ld", "prov-n")) {
  format <- match.arg(format)
  prov <- if (methods::is(x, "PhysioExperiment")) provenance(x)
          else if (is.data.frame(x)) x
          else stop("`x` must be a PhysioExperiment or a provenance data.frame",
                    call. = FALSE)
  if (format == "prov-n") {
    writeLines(.toProvN(prov), path)
  } else {
    doc <- if (format == "json-ld") .toProvJsonLd(prov) else .toProvJson(prov)
    writeLines(jsonlite::toJSON(doc, auto_unbox = TRUE, pretty = TRUE,
                                null = "null", na = "null", digits = NA), path)
  }
  invisible(path)
}

#' Read a W3C PROV interchange file back into a provenance table
#'
#' Inverse of \code{\link{writeProv}}. The format is auto-detected from the file
#' contents (PROV-N text, PROV JSON-LD, or PROV-JSON).
#'
#' @param path Path to a PROV document written by \code{\link{writeProv}}.
#' @return A provenance \code{data.frame} with the same columns as
#'   \code{\link[PhysioCore]{provenance}}.
#' @seealso \code{\link{writeProv}}
#' @examples
#' pe <- PhysioExperiment(
#'   S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)), samplingRate = 100)
#' pe <- logStep(pe, "import")
#' tf <- tempfile(fileext = ".json")
#' writeProv(pe, tf)
#' readProv(tf)
#' @export
readProv <- function(path) {
  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
  if (grepl("^\\s*document", txt)) return(.provNToDf(txt))
  doc <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  if (!is.null(doc[["@graph"]]) || !is.null(doc[["@context"]])) {
    return(.provJsonLdToDf(doc))
  }
  .provJsonToDf(doc)
}

# Write a provenance sidecar next to a data file (used by writePhysioHDF5 /
# writeBIDS). Silent no-op when the object has no provenance.
.writeProvSidecar <- function(x, path, format = "prov-json") {
  if (!methods::is(x, "PhysioExperiment")) return(invisible(NULL))
  prov <- tryCatch(provenance(x), error = function(e) NULL)
  if (is.null(prov) || nrow(prov) == 0L) return(invisible(NULL))
  ext <- if (format == "prov-n") ".provn" else ".prov.json"
  side <- paste0(tools::file_path_sans_ext(path), ext)
  tryCatch(writeProv(prov, side, format = format),
           error = function(e) invisible(NULL))
  invisible(side)
}
