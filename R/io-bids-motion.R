# Motion-BIDS, continuous _physio.tsv.gz recordings, and BIDS derivatives.
# Extends the core BIDS I/O (io-bids.R) with the motion datatype (Jeung et al.
# 2023), gzip physio streams (attached via MultiRatePhysioExperiment when the
# rate differs from the main recording), and a derivatives layout whose
# dataset_description.json GeneratedBy is populated from the object provenance.

# BIDS filename base "sub-X[_ses-Y]_task-Z[_extras][_run-NN]" (entities in the
# BIDS canonical order); extras go between task and run.
.bids_base <- function(subject, session, task, run, extras = character(0)) {
  b <- paste0("sub-", subject)
  if (!is.null(session)) b <- paste0(b, "_ses-", session)
  if (!is.null(task)) b <- paste0(b, "_task-", task)
  for (e in extras) b <- paste0(b, "_", e)
  if (!is.null(run)) b <- paste0(b, "_run-", sprintf("%02d", run))
  b
}

.bids_datadir <- function(root, subject, session, datatype) {
  parts <- c(root, paste0("sub-", subject))
  if (!is.null(session)) parts <- c(parts, paste0("ses-", session))
  parts <- c(parts, datatype)
  do.call(file.path, as.list(parts))
}

# GeneratedBy list for dataset_description.json, populated from provenance().
.bidsGeneratedBy <- function(x = NULL) {
  base <- list(Name = "PhysioIO",
               Version = as.character(utils::packageVersion("PhysioIO")))
  prov <- if (is.null(x)) NULL
          else tryCatch(PhysioCore::provenance(x), error = function(e) NULL)
  if (!is.null(prov) && nrow(prov) > 0) {
    base$Description <- paste(unique(prov$activity), collapse = " -> ")
  }
  list(base)
}

# ---- Motion-BIDS ------------------------------------------------------------

#' Write a Motion-BIDS recording
#'
#' Writes a motion-capture \code{PhysioExperiment} in the BIDS \code{motion}
#' datatype (Jeung et al. 2023): a headerless \code{_motion.tsv}, a
#' \code{_channels.tsv} carrying \code{tracked_point}/\code{component}, and a
#' \code{_motion.json} sidecar with \code{SamplingFrequency} and
#' \code{TrackingSystemName}.
#'
#' @param x A \code{PhysioExperiment} of motion data (2D assay). \code{colData}
#'   columns \code{label}, \code{type}, \code{unit}, \code{tracked_point} and
#'   \code{component} are used when present.
#' @param bids_root BIDS dataset root.
#' @param subject,task Subject label and task label.
#' @param session,run Optional session label and run number.
#' @param tracking_system Tracking-system label (the \code{tracksys-} entity and
#'   \code{TrackingSystemName}).
#' @param overwrite Overwrite existing files (default \code{FALSE}).
#' @return The data directory path, invisibly.
#' @references Jeung, S., et al. (2023). Motion-BIDS. \emph{Scientific Data}.
#' @seealso \code{\link{readBIDSMotion}}
#' @export
writeBIDSMotion <- function(x, bids_root, subject, task, session = NULL,
                            run = NULL, tracking_system = "unspecified",
                            overwrite = FALSE) {
  stopifnot(inherits(x, "PhysioExperiment"))
  data <- as.matrix(SummarizedExperiment::assay(x, defaultAssay(x)))
  if (length(dim(data)) != 2L) stop("motion data must be 2D", call. = FALSE)
  nchan <- ncol(data)
  cd <- SummarizedExperiment::colData(x)
  col <- function(nm, default) if (nm %in% names(cd)) as.character(cd[[nm]])
                               else rep(default, nchan)
  labels <- col("label", "")
  labels[!nzchar(labels)] <- paste0("chan", which(!nzchar(labels)))

  ddir <- .bids_datadir(bids_root, subject, session, "motion")
  if (!dir.exists(ddir)) dir.create(ddir, recursive = TRUE)
  base <- .bids_base(subject, session, task, run,
                     extras = paste0("tracksys-", tracking_system))

  motion_tsv <- file.path(ddir, paste0(base, "_motion.tsv"))
  if (file.exists(motion_tsv) && !overwrite) {
    stop("file exists (use overwrite = TRUE): ", motion_tsv, call. = FALSE)
  }
  # Motion-BIDS: the _motion.tsv has NO column header row
  utils::write.table(data, motion_tsv, sep = "\t", row.names = FALSE,
                     col.names = FALSE, na = "n/a", quote = FALSE)

  channels <- data.frame(
    name = labels,
    type = col("type", "POS"),
    tracked_point = col("tracked_point", "n/a"),
    component = col("component", "n/a"),
    units = col("unit", "n/a"),
    sampling_frequency = samplingRate(x),
    stringsAsFactors = FALSE)
  utils::write.table(channels, file.path(ddir, paste0(base, "_channels.tsv")),
                     sep = "\t", row.names = FALSE, quote = FALSE, na = "n/a")

  sidecar <- list(TaskName = task, SamplingFrequency = samplingRate(x),
                  TrackingSystemName = tracking_system,
                  MotionChannelCount = nchan, RecordingType = "continuous")
  writeLines(jsonlite::toJSON(sidecar, auto_unbox = TRUE, pretty = TRUE),
             file.path(ddir, paste0(base, "_motion.json")))

  desc_file <- file.path(bids_root, "dataset_description.json")
  if (!file.exists(desc_file)) {
    .writeBIDSDescription(bids_root, generated_by = .bidsGeneratedBy(x))
  }
  invisible(ddir)
}

#' Read a Motion-BIDS recording
#'
#' @param bids_root BIDS dataset root.
#' @param subject,task Subject and task labels.
#' @param session,run Optional session label and run number.
#' @param tracking_system Optional tracking-system label to disambiguate.
#' @return A \code{PhysioExperiment} with the motion data, \code{colData}
#'   carrying \code{tracked_point}/\code{component}/units, and the sampling rate.
#' @seealso \code{\link{writeBIDSMotion}}
#' @export
readBIDSMotion <- function(bids_root, subject, task, session = NULL,
                           run = NULL, tracking_system = NULL) {
  ddir <- .bids_datadir(bids_root, subject, session, "motion")
  if (!dir.exists(ddir)) stop("motion directory not found: ", ddir, call. = FALSE)
  if (is.null(tracking_system)) {
    # anchor at the entity boundary so e.g. task-walk does not match task-walking,
    # and require an unambiguous match
    pat <- paste0("^", .bids_base(subject, session, task, run),
                  "(_.*)?_motion\\.tsv$")
    hit <- list.files(ddir, pattern = pat, full.names = TRUE)
    if (length(hit) == 0L) {
      stop("no _motion.tsv found for the given entities", call. = FALSE)
    }
    if (length(hit) > 1L) {
      stop("multiple motion files match; specify tracking_system: ",
           paste(basename(hit), collapse = ", "), call. = FALSE)
    }
    motion_tsv <- hit[1]
  } else {
    base <- .bids_base(subject, session, task, run,
                       extras = paste0("tracksys-", tracking_system))
    motion_tsv <- file.path(ddir, paste0(base, "_motion.tsv"))
  }
  if (!file.exists(motion_tsv)) stop("motion file not found: ", motion_tsv, call. = FALSE)
  prefix <- sub("_motion\\.tsv$", "", motion_tsv)

  df <- utils::read.delim(motion_tsv, header = FALSE, na.strings = "n/a")
  data <- suppressWarnings(matrix(as.numeric(as.matrix(df)), nrow = nrow(df)))
  ch <- utils::read.delim(paste0(prefix, "_channels.tsv"),
                          stringsAsFactors = FALSE, na.strings = "n/a")
  sidecar <- jsonlite::fromJSON(paste0(prefix, "_motion.json"))
  if (length(ch$name) != ncol(data)) {
    stop(sprintf("_channels.tsv describes %d channels but _motion.tsv has %d columns",
                 length(ch$name), ncol(data)), call. = FALSE)
  }
  colnames(data) <- ch$name

  PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = data),
    colData = S4Vectors::DataFrame(
      label = ch$name, type = ch$type,
      unit = if (!is.null(ch$units)) ch$units else "n/a",
      tracked_point = if (!is.null(ch$tracked_point)) ch$tracked_point else "n/a",
      component = if (!is.null(ch$component)) ch$component else "n/a"),
    metadata = list(bids = list(subject = subject, session = session,
                                task = task, run = run, datatype = "motion"),
                    tracking_system_name = sidecar$TrackingSystemName %||% NA_character_),
    samplingRate = sidecar$SamplingFrequency)
}

# ---- continuous _physio.tsv.gz ----------------------------------------------

#' Write a BIDS continuous physiological recording
#'
#' Writes a gzipped \code{_physio.tsv.gz} (headerless, columns defined in the
#' JSON) plus a \code{_physio.json} sidecar with \code{SamplingFrequency},
#' \code{StartTime} and \code{Columns}.
#'
#' @param x A \code{PhysioExperiment} (2D assay).
#' @param bids_root,subject,task,session,run BIDS entities.
#' @param start_time Recording start time relative to the main recording, in
#'   seconds (BIDS \code{StartTime}; default 0).
#' @param overwrite Overwrite existing files (default \code{FALSE}).
#' @return The written \code{.tsv.gz} path, invisibly.
#' @seealso \code{\link{readBIDSPhysio}}, \code{\link{attachBIDSPhysio}}
#' @export
writeBIDSPhysio <- function(x, bids_root, subject, task, session = NULL,
                            run = NULL, start_time = 0, overwrite = FALSE) {
  stopifnot(inherits(x, "PhysioExperiment"))
  data <- as.matrix(SummarizedExperiment::assay(x, defaultAssay(x)))
  cols <- channelNames(x)
  if (length(cols) != ncol(data)) cols <- paste0("col", seq_len(ncol(data)))

  ddir <- .bids_datadir(bids_root, subject, session, "beh")
  if (!dir.exists(ddir)) dir.create(ddir, recursive = TRUE)
  base <- .bids_base(subject, session, task, run)
  tsvgz <- file.path(ddir, paste0(base, "_physio.tsv.gz"))
  if (file.exists(tsvgz) && !overwrite) {
    stop("file exists (use overwrite = TRUE): ", tsvgz, call. = FALSE)
  }
  con <- gzfile(tsvgz, "w")
  utils::write.table(data, con, sep = "\t", row.names = FALSE,
                     col.names = FALSE, na = "n/a", quote = FALSE)
  close(con)

  sidecar <- list(SamplingFrequency = samplingRate(x),
                  StartTime = start_time, Columns = as.list(cols))
  writeLines(jsonlite::toJSON(sidecar, auto_unbox = TRUE, pretty = TRUE),
             file.path(ddir, paste0(base, "_physio.json")))
  invisible(tsvgz)
}

#' Read a BIDS continuous physiological recording
#'
#' @param path Path to the \code{_physio.tsv.gz} file (its \code{_physio.json}
#'   sidecar is read alongside).
#' @return A \code{PhysioExperiment} with the physio signals; \code{StartTime}
#'   is stored in \code{metadata()$bids_start_time}.
#' @seealso \code{\link{writeBIDSPhysio}}, \code{\link{attachBIDSPhysio}}
#' @export
readBIDSPhysio <- function(path) {
  if (!file.exists(path)) stop("physio file not found: ", path, call. = FALSE)
  json_path <- sub("\\.tsv\\.gz$", ".json", path)
  sidecar <- jsonlite::fromJSON(json_path)
  con <- gzfile(path, "r")
  df <- utils::read.delim(con, header = FALSE, na.strings = "n/a")
  close(con)
  data <- suppressWarnings(matrix(as.numeric(as.matrix(df)), nrow = nrow(df)))
  cols <- unlist(sidecar$Columns)
  if (length(cols) == ncol(data)) colnames(data) <- cols
  PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = data),
    colData = if (length(cols) == ncol(data))
      S4Vectors::DataFrame(label = cols) else NULL,
    metadata = list(bids_start_time = sidecar$StartTime %||% 0,
                    source_format = "physio"),
    samplingRate = sidecar$SamplingFrequency)
}

#' Attach a physio recording to a main recording as an aligned stream
#'
#' Combines a main recording and a \code{_physio} recording into a
#' \code{MultiRatePhysioExperiment}, using the physio's \code{StartTime} as its
#' clock offset. The two keep their own sampling rates.
#'
#' @param main A \code{PhysioExperiment} (the primary recording).
#' @param physio A \code{PhysioExperiment} from \code{\link{readBIDSPhysio}}.
#' @return A \code{\link[PhysioCore]{MultiRatePhysioExperiment}}.
#' @seealso \code{\link{readBIDSPhysio}}
#' @export
attachBIDSPhysio <- function(main, physio) {
  stopifnot(inherits(main, "PhysioExperiment"), inherits(physio, "PhysioExperiment"))
  st <- S4Vectors::metadata(physio)$bids_start_time %||% 0
  PhysioCore::MultiRatePhysioExperiment(
    recording = main, physio = physio, offsets = c(physio = st))
}

# ---- BIDS derivatives -------------------------------------------------------

#' Write a BIDS derivative recording
#'
#' Writes \code{x} as a derivative under \code{deriv_root} with a
#' \code{desc-<label>} entity, and a derivative \code{dataset_description.json}
#' whose \code{GeneratedBy} is populated from the object's provenance
#' (\code{\link[PhysioCore]{provenance}}). The signals are stored as a gzipped
#' \code{_physio.tsv.gz} plus JSON.
#'
#' @param x A \code{PhysioExperiment} (typically a processed derivative).
#' @param deriv_root Derivative dataset root (e.g.
#'   \code{"<bids>/derivatives/physio-clean"}).
#' @param subject,task,session,run BIDS entities.
#' @param desc The \code{desc-} label (e.g. \code{"clean"}).
#' @param pipeline_name Name recorded in \code{GeneratedBy} (default
#'   \code{basename(deriv_root)}).
#' @param overwrite Overwrite existing files (default \code{FALSE}).
#' @return The written data path, invisibly.
#' @seealso \code{\link{readBIDSDerivatives}}
#' @export
writeBIDSDerivative <- function(x, deriv_root, subject, task, desc,
                                session = NULL, run = NULL,
                                pipeline_name = NULL, overwrite = FALSE) {
  stopifnot(inherits(x, "PhysioExperiment"))
  if (!dir.exists(deriv_root)) dir.create(deriv_root, recursive = TRUE)
  gb <- .bidsGeneratedBy(x)
  if (!is.null(pipeline_name)) gb[[1]]$Name <- pipeline_name
  .writeBIDSDescription(deriv_root, generated_by = gb, dataset_type = "derivative",
                        name = if (is.null(pipeline_name)) basename(deriv_root)
                               else pipeline_name)

  ddir <- .bids_datadir(deriv_root, subject, session, "beh")
  if (!dir.exists(ddir)) dir.create(ddir, recursive = TRUE)
  # desc is the last entity, after run (BIDS canonical order)
  base <- paste0(.bids_base(subject, session, task, run), "_desc-", desc)
  data <- as.matrix(SummarizedExperiment::assay(x, defaultAssay(x)))
  cols <- channelNames(x)
  if (length(cols) != ncol(data)) cols <- paste0("col", seq_len(ncol(data)))
  tsvgz <- file.path(ddir, paste0(base, "_physio.tsv.gz"))
  if (file.exists(tsvgz) && !overwrite) {
    stop("file exists (use overwrite = TRUE): ", tsvgz, call. = FALSE)
  }
  con <- gzfile(tsvgz, "w")
  utils::write.table(data, con, sep = "\t", row.names = FALSE,
                     col.names = FALSE, na = "n/a", quote = FALSE)
  close(con)
  writeLines(jsonlite::toJSON(
    list(SamplingFrequency = samplingRate(x), StartTime = 0,
         Columns = as.list(cols), Description = paste0("desc-", desc)),
    auto_unbox = TRUE, pretty = TRUE),
    file.path(ddir, paste0(base, "_physio.json")))
  invisible(tsvgz)
}

#' Read the derivative recordings of a subject
#'
#' @param deriv_root Derivative dataset root.
#' @param subject Subject label.
#' @param session Optional session label.
#' @return A named list of \code{PhysioExperiment} objects, one per
#'   \code{desc-<label>} derivative found for the subject.
#' @seealso \code{\link{writeBIDSDerivative}}
#' @export
readBIDSDerivatives <- function(deriv_root, subject, session = NULL) {
  ddir <- .bids_datadir(deriv_root, subject, session, "beh")
  if (!dir.exists(ddir)) return(list())
  files <- list.files(ddir, pattern = "_desc-[^_]+_physio\\.tsv\\.gz$",
                      full.names = TRUE)
  out <- lapply(files, readBIDSPhysio)
  descs <- sub(".*_desc-([^_]+).*", "\\1", basename(files))
  stats::setNames(out, descs)
}
