# Apache Arrow / Parquet columnar I/O for PhysioExperiment objects
#
# writeParquet() serialises a PhysioExperiment (or MultiRatePhysioExperiment)
# to a self-describing directory of Parquet tables plus JSON sidecars, and
# readParquet() reconstructs it exactly. Parquet's columnar layout makes the
# assays directly queryable by DuckDB via read_parquet() for out-of-core
# analytics (see registerParquetAssay()).
#
# arrow is an OPTIONAL backend (Suggests): every entry point guards on
# requireNamespace("arrow").

.PARQUET_FORMAT  <- "physio-parquet"
.PARQUET_VERSION <- 1L

.need_arrow <- function() {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Package 'arrow' is required for Parquet I/O. ",
         "Install with: install.packages('arrow')", call. = FALSE)
  }
}

# Metadata and the provenance entries list are arbitrary R structures (nested
# lists, POSIXct, integer vs double, Date, quotes) that only a type-preserving
# serialiser reproduces exactly. jsonlite::serializeJSON with digits = 17
# round-trips any such object bit-for-bit (17 significant digits recover every
# IEEE-754 double), so both are stored this way rather than via the lossy
# scalar-only metadata JSON helper.
.write_rjson <- function(obj, path) {
  writeLines(jsonlite::serializeJSON(obj, digits = 17), path)
}

.read_rjson <- function(path) {
  jsonlite::unserializeJSON(paste(readLines(path, warn = FALSE),
                                  collapse = "\n"))
}

# Row names of a DataFrame as a JSON-friendly list, or NA when unset.
.rn_or_na <- function(rn) {
  if (is.null(rn) || length(rn) == 0) NA_character_ else as.list(rn)
}

#' Write a PhysioExperiment to a Parquet dataset directory
#'
#' Serialises a `PhysioExperiment` (or `MultiRatePhysioExperiment`) to a
#' directory of Apache Parquet tables and JSON sidecars. Each assay is stored
#' as a columnar Parquet table (one column per channel), and `colData`,
#' `rowData`, events, metadata, provenance and per-assay sampling rates are
#' stored alongside so that `readParquet()` reproduces the object exactly.
#'
#' Parquet is a columnar, self-describing format that DuckDB can query in place
#' via `read_parquet()`, enabling out-of-core aggregation over the assays
#' without loading them into R (see [registerParquetAssay()]).
#'
#' A `MultiRatePhysioExperiment` is written as a `streams/` sub-directory (one
#' Parquet dataset per stream) plus its common clock (t0, reference rate,
#' per-stream offsets).
#'
#' @param x A `PhysioExperiment` or `MultiRatePhysioExperiment`.
#' @param dir Output directory (created if absent).
#' @param overwrite Overwrite a non-empty directory (default `FALSE`).
#' @return The output `dir`, invisibly.
#' @references
#'   Apache Software Foundation. "Apache Parquet."
#'   \url{https://parquet.apache.org/}.
#' @seealso [readParquet()], [registerParquetAssay()], [writePhysioHDF5()]
#' @export
#' @examples
#' if (requireNamespace("arrow", quietly = TRUE)) {
#'   pe <- PhysioExperiment(
#'     assays = S4Vectors::SimpleList(raw = matrix(rnorm(30), 10, 3)),
#'     colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz")),
#'     samplingRate = 256)
#'   d <- tempfile("pe-parquet")
#'   writeParquet(pe, d)
#'   pe2 <- readParquet(d)
#' }
writeParquet <- function(x, dir, overwrite = FALSE) {
  .need_arrow()
  if (!inherits(x, "PhysioExperiment") &&
      !inherits(x, "MultiRatePhysioExperiment")) {
    stop("'x' must be a PhysioExperiment or MultiRatePhysioExperiment.",
         call. = FALSE)
  }
  if (dir.exists(dir) && length(list.files(dir)) > 0) {
    if (!overwrite) {
      stop("directory exists and is not empty (use overwrite = TRUE): ", dir,
           call. = FALSE)
    }
    # Clear stale contents so a previous write's assays/streams do not survive.
    unlink(dir, recursive = TRUE)
  }
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)

  if (inherits(x, "MultiRatePhysioExperiment")) {
    .writeParquetMultiRate(x, dir)
  } else {
    .writeParquetPE(x, dir)
  }
  invisible(dir)
}

# Serialise a single PhysioExperiment into `dir`.
.writeParquetPE <- function(x, dir) {
  assay_names <- SummarizedExperiment::assayNames(x)
  adir <- file.path(dir, "assays")
  if (!dir.exists(adir)) dir.create(adir, recursive = TRUE)

  assay_dims <- list()
  for (a in assay_names) {
    d <- as.array(SummarizedExperiment::assay(x, a))
    dm <- dim(d)
    # Flatten >2D assays column-major to 2D; the shape is restored from the
    # manifest on read. Preserve the storage mode (integer stays integer).
    d2 <- if (length(dm) > 2) {
      matrix(as.vector(d), nrow = dm[1])
    } else {
      d
    }
    df <- as.data.frame(d2)
    names(df) <- paste0("ch", seq_len(ncol(df)))
    arrow::write_parquet(df, file.path(adir, paste0(a, ".parquet")))
    assay_dims[[a]] <- as.integer(dm)
  }

  # colData / rowData (arrow drops the row count of a 0-column table, so only
  # write tables that actually carry columns; dims and rownames live in the
  # manifest).
  cd0 <- SummarizedExperiment::colData(x)
  rd0 <- SummarizedExperiment::rowData(x)
  cd_rn <- rownames(cd0)
  rd_rn <- rownames(rd0)
  cd <- as.data.frame(cd0)
  has_coldata <- ncol(cd) > 0
  if (has_coldata) {
    arrow::write_parquet(`rownames<-`(cd, NULL),
                         file.path(dir, "colData.parquet"))
  }
  rd <- as.data.frame(rd0)
  has_rowdata <- ncol(rd) > 0
  if (has_rowdata) {
    arrow::write_parquet(`rownames<-`(rd, NULL),
                         file.path(dir, "rowData.parquet"))
  }

  # Events (onset / duration / type / value).
  ev <- tryCatch(getEvents(x), error = function(e) NULL)
  has_events <- !is.null(ev) && nEvents(ev) > 0
  if (has_events) {
    arrow::write_parquet(as.data.frame(ev@events),
                         file.path(dir, "events.parquet"))
  }

  # Extra metadata (events and provenance stripped; serialised separately).
  # Per-assay sampling rates live in metadata$assay_sampling_rates when the
  # object actually customised them, so serialising metadata verbatim restores
  # them exactly without injecting a key a plain object never had.
  meta <- S4Vectors::metadata(x)
  meta$events <- NULL
  meta$provenance <- NULL
  .write_rjson(meta, file.path(dir, "metadata.json"))

  # Provenance: serialise the raw entries list (metadata$provenance).
  prov_entries <- S4Vectors::metadata(x)[["provenance"]]
  has_prov <- !is.null(prov_entries) && length(prov_entries) > 0
  if (has_prov) {
    .write_rjson(prov_entries, file.path(dir, "provenance.json"))
  }

  manifest <- list(
    format = .PARQUET_FORMAT,
    version = .PARQUET_VERSION,
    class = "PhysioExperiment",
    samplingRate = as.numeric(samplingRate(x)),
    n_channels = as.integer(nChannels(x)),
    assays = as.list(assay_names),
    assay_dims = assay_dims,
    default_assay = defaultAssay(x),
    metadata_order = as.list(names(S4Vectors::metadata(x))),
    coldata_rownames = .rn_or_na(cd_rn),
    rowdata_rownames = .rn_or_na(rd_rn),
    has_coldata = has_coldata,
    has_rowdata = has_rowdata,
    has_events = has_events,
    has_provenance = has_prov)
  writeLines(
    jsonlite::toJSON(manifest, auto_unbox = TRUE, null = "null",
                     na = "null", digits = NA),
    file.path(dir, "manifest.json"))
  invisible(dir)
}

# Serialise a MultiRatePhysioExperiment (streams + common clock).
.writeParquetMultiRate <- function(x, dir) {
  streams <- PhysioCore::streams(x)
  sdir <- file.path(dir, "streams")
  if (!dir.exists(sdir)) dir.create(sdir, recursive = TRUE)
  for (nm in names(streams)) {
    .writeParquetPE(streams[[nm]], file.path(sdir, nm))
  }
  clock <- PhysioCore::commonClock(x)
  manifest <- list(
    format = .PARQUET_FORMAT,
    version = .PARQUET_VERSION,
    class = "MultiRatePhysioExperiment",
    streams = as.list(names(streams)),
    stream_rates = as.list(PhysioCore::streamRates(x)),
    t0 = as.numeric(clock$t0),
    reference_rate = as.numeric(clock$reference_rate),
    offsets = as.list(clock$offsets))
  writeLines(
    jsonlite::toJSON(manifest, auto_unbox = TRUE, null = "null",
                     na = "null", digits = NA),
    file.path(dir, "manifest.json"))
  invisible(dir)
}

#' Read a PhysioExperiment from a Parquet dataset directory
#'
#' Inverse of [writeParquet()]: reconstructs a `PhysioExperiment` (or
#' `MultiRatePhysioExperiment`) from a directory written by `writeParquet()`.
#'
#' @param dir A directory written by [writeParquet()].
#' @return A `PhysioExperiment` or `MultiRatePhysioExperiment`.
#' @seealso [writeParquet()]
#' @export
#' @examples
#' if (requireNamespace("arrow", quietly = TRUE)) {
#'   pe <- PhysioExperiment(
#'     assays = S4Vectors::SimpleList(raw = matrix(rnorm(30), 10, 3)),
#'     samplingRate = 256)
#'   d <- tempfile("pe-parquet")
#'   writeParquet(pe, d)
#'   readParquet(d)
#' }
readParquet <- function(dir) {
  .need_arrow()
  mpath <- file.path(dir, "manifest.json")
  if (!file.exists(mpath)) {
    stop("not a physio-parquet directory (no manifest.json): ", dir,
         call. = FALSE)
  }
  manifest <- jsonlite::fromJSON(readLines(mpath, warn = FALSE),
                                 simplifyVector = FALSE)
  if (!identical(manifest$format, .PARQUET_FORMAT)) {
    stop("unrecognised Parquet dataset format: ",
         manifest$format %||% "(none)", call. = FALSE)
  }
  if (identical(manifest$class, "MultiRatePhysioExperiment")) {
    .readParquetMultiRate(dir, manifest)
  } else {
    .readParquetPE(dir, manifest)
  }
}

.readParquetPE <- function(dir, manifest) {
  assay_names <- unlist(manifest$assays)
  assays <- S4Vectors::SimpleList()
  for (a in assay_names) {
    df <- arrow::read_parquet(file.path(dir, "assays", paste0(a, ".parquet")))
    m <- as.matrix(df)
    dimnames(m) <- NULL
    dm <- as.integer(unlist(manifest$assay_dims[[a]]))
    # Leave assay dimnames unset: channel identity is carried by colData, and
    # forcing colnames here would make the constructor synthesise colData
    # rownames the original object did not have. Preserve the storage mode.
    d <- if (length(dm) > 2) array(as.vector(m), dim = dm) else m
    assays[[a]] <- d
  }

  col_data <- if (isTRUE(manifest$has_coldata)) {
    S4Vectors::DataFrame(as.data.frame(
      arrow::read_parquet(file.path(dir, "colData.parquet")),
      stringsAsFactors = FALSE))
  } else {
    n <- as.integer(manifest$n_channels %||% 0L)
    S4Vectors::make_zero_col_DFrame(n)
  }
  cd_rn <- manifest$coldata_rownames
  if (!is.null(cd_rn) && !identical(cd_rn, NA_character_)) {
    rownames(col_data) <- unlist(cd_rn)
  }
  row_data <- if (isTRUE(manifest$has_rowdata)) {
    rd <- S4Vectors::DataFrame(as.data.frame(
      arrow::read_parquet(file.path(dir, "rowData.parquet")),
      stringsAsFactors = FALSE))
    rd_rn <- manifest$rowdata_rownames
    if (!is.null(rd_rn) && !identical(rd_rn, NA_character_)) {
      rownames(rd) <- unlist(rd_rn)
    }
    rd
  } else {
    NULL
  }

  meta <- .read_rjson(file.path(dir, "metadata.json"))
  if (!is.list(meta)) meta <- list()

  # Per-assay sampling rates ride along in metadata$assay_sampling_rates
  # (present only when the source object customised them).
  args <- list(assays = assays, colData = col_data, metadata = meta,
               samplingRate = as.numeric(manifest$samplingRate))
  if (!is.null(row_data)) args$rowData <- row_data
  pe <- do.call(PhysioExperiment, args)

  # Restore events.
  if (isTRUE(manifest$has_events)) {
    edf <- as.data.frame(arrow::read_parquet(file.path(dir, "events.parquet")))
    pe <- setEvents(pe, PhysioEvents(
      onset = as.numeric(edf$onset), duration = as.numeric(edf$duration),
      type = as.character(edf$type), value = as.character(edf$value)))
  }

  # Restore provenance (raw entries list into metadata).
  if (isTRUE(manifest$has_provenance)) {
    S4Vectors::metadata(pe)[["provenance"]] <-
      .read_rjson(file.path(dir, "provenance.json"))
  }

  # Restore the original metadata key order (events/provenance were appended
  # out of their original position above).
  mo <- unlist(manifest$metadata_order)
  if (!is.null(mo)) {
    md <- S4Vectors::metadata(pe)
    ordered <- c(mo[mo %in% names(md)], setdiff(names(md), mo))
    S4Vectors::metadata(pe) <- md[ordered]
  }
  pe
}

.readParquetMultiRate <- function(dir, manifest) {
  stream_names <- unlist(manifest$streams)
  streams <- lapply(stream_names, function(nm) {
    sdir <- file.path(dir, "streams", nm)
    .readParquetPE(sdir, jsonlite::fromJSON(
      readLines(file.path(sdir, "manifest.json"), warn = FALSE),
      simplifyVector = FALSE))
  })
  names(streams) <- stream_names
  offsets <- unlist(lapply(manifest$offsets, as.numeric))
  PhysioCore::MultiRatePhysioExperiment(
    streams = streams,
    t0 = as.numeric(manifest$t0 %||% 0),
    reference_rate = as.numeric(manifest$reference_rate),
    offsets = offsets)
}

#' Register a Parquet-backed assay as a DuckDB view for out-of-core queries
#'
#' Creates (or replaces) a DuckDB view over an assay Parquet file written by
#' [writeParquet()], using DuckDB's `read_parquet()` so that aggregates are
#' computed directly over the file without loading it into R. The view columns
#' are `ch1`, `ch2`, ... (one per channel).
#'
#' @param con A DuckDB connection (from [connectDatabase()]).
#' @param dir A directory written by [writeParquet()].
#' @param view_name Name of the DuckDB view to create (default `"signals"`).
#' @param assay Assay to expose; defaults to the manifest's default assay.
#' @return The `view_name`, invisibly.
#' @seealso [writeParquet()], [registerExperiment()]
#' @export
registerParquetAssay <- function(con, dir, view_name = "signals",
                                 assay = NULL) {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("Package 'duckdb' is required for DuckDB Parquet views.", call. = FALSE)
  }
  mpath <- file.path(dir, "manifest.json")
  if (!file.exists(mpath)) {
    stop("not a physio-parquet directory (no manifest.json): ", dir,
         call. = FALSE)
  }
  manifest <- jsonlite::fromJSON(readLines(mpath, warn = FALSE),
                                 simplifyVector = FALSE)
  if (is.null(assay)) assay <- manifest$default_assay
  if (is.null(assay) || is.na(assay)) assay <- unlist(manifest$assays)[1]
  pq <- normalizePath(file.path(dir, "assays", paste0(assay, ".parquet")),
                      mustWork = TRUE)
  # Escape single quotes in the path for the SQL string literal.
  pq_sql <- gsub("'", "''", pq)
  DBI::dbExecute(con, sprintf(
    "CREATE OR REPLACE VIEW %s AS SELECT * FROM read_parquet('%s')",
    DBI::dbQuoteIdentifier(con, view_name), pq_sql))
  invisible(view_name)
}
