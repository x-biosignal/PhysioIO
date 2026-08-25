#' BIDS Format Support for PhysioExperiment
#'
#' Functions for reading and writing data in BIDS (Brain Imaging Data Structure) format.
#' Supports BIDS-EEG and BIDS-iEEG specifications.

#' Read PhysioExperiment from BIDS dataset
#'
#' Reads EEG/iEEG data from a BIDS-compliant directory structure.
#'
#' @param bids_root Path to the BIDS dataset root directory.
#' @param subject Subject identifier (without 'sub-' prefix).
#' @param session Session identifier (without 'ses-' prefix). Optional.
#' @param task Task name.
#' @param run Run number. Optional.
#' @param modality Data modality: "eeg" or "ieeg".
#' @param load_events If TRUE, loads events from the events.tsv file.
#' @return A PhysioExperiment object.
#' @references
#'   Gorgolewski KJ, et al. (2016). "The brain imaging data structure,
#'   a format for organizing and describing outputs of neuroimaging
#'   experiments." Scientific Data, 3, 160044.
#'   doi:10.1038/sdata.2016.44
#' @seealso \code{\link{writeBIDS}}, \code{\link{validateBIDS}},
#'   \code{\link{readEDF}}, \code{\link{listBIDSSubjects}}
#' @export
#' @examples
#' # Write a minimal BIDS dataset to a temporary directory, then read it back
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
#'   colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
#'   samplingRate = 100
#' )
#' bids_root <- file.path(tempdir(), "bids-demo")
#' writeBIDS(pe, bids_root, subject = "01", task = "rest")
#'
#' # Read EEG data back from the BIDS dataset
#' pe_in <- readBIDS(bids_root, subject = "01", task = "rest")
#' dim(SummarizedExperiment::assay(pe_in, "raw"))
#'
#' unlink(bids_root, recursive = TRUE)
readBIDS <- function(bids_root, subject, session = NULL, task,
                     run = NULL, modality = c("eeg", "ieeg"),
                     load_events = TRUE) {
  modality <- match.arg(modality)

  if (!dir.exists(bids_root)) {
    stop("BIDS root directory not found: ", bids_root, call. = FALSE)
  }

  # Build file path
  subj_dir <- paste0("sub-", subject)
  path_parts <- c(bids_root, subj_dir)

  if (!is.null(session)) {
    path_parts <- c(path_parts, paste0("ses-", session))
  }
  path_parts <- c(path_parts, modality)

  data_dir <- do.call(file.path, as.list(path_parts))

  if (!dir.exists(data_dir)) {
    stop("Data directory not found: ", data_dir, call. = FALSE)
  }

  # Build filename pattern
  filename_parts <- paste0("sub-", subject)
  if (!is.null(session)) {
    filename_parts <- paste0(filename_parts, "_ses-", session)
  }
  filename_parts <- paste0(filename_parts, "_task-", task)
  if (!is.null(run)) {
    filename_parts <- paste0(filename_parts, "_run-", sprintf("%02d", run))
  }
  filename_parts <- paste0(filename_parts, "_", modality)

  # Find data file (support EDF, BDF, or SET formats)
  data_files <- list.files(data_dir, pattern = paste0("^", filename_parts, "\\.(edf|bdf|set)$"),
                           full.names = TRUE, ignore.case = TRUE)

  if (length(data_files) == 0) {
    stop("No data file found matching pattern: ", filename_parts, call. = FALSE)
  }

  data_file <- data_files[1]

  # Read the data file
  ext <- tolower(tools::file_ext(data_file))
  if (ext == "edf") {
    pe <- readEDF(data_file)
  } else if (ext == "bdf") {
    pe <- readBDF(data_file)
  } else if (ext == "set") {
    if (!requireNamespace("R.matlab", quietly = TRUE)) {
      stop("Package 'R.matlab' required for reading SET files. ",
           "Install with: install.packages('R.matlab')", call. = FALSE)
    }
    pe <- readMAT(data_file, data_var = "EEG")
  } else {
    stop("Unsupported file format: ", ext, ". Supported formats: EDF, BDF, SET.", call. = FALSE)
  }

  # Load channels.tsv if available
  channels_file <- file.path(data_dir, paste0(filename_parts, "_channels.tsv"))
  if (file.exists(channels_file)) {
    channels_df <- utils::read.delim(channels_file, stringsAsFactors = FALSE)
    pe <- .applyBIDSChannelInfo(pe, channels_df)
  }

  # Load events.tsv if requested and available
  if (load_events) {
    events_file <- file.path(data_dir, paste0(filename_parts, "_events.tsv"))
    if (file.exists(events_file)) {
      events_df <- utils::read.delim(events_file, stringsAsFactors = FALSE)
      pe <- .applyBIDSEvents(pe, events_df)
    }
  }

  # Load electrodes.tsv if available (for electrode positions)
  electrodes_file <- file.path(data_dir, paste0(filename_parts, "_electrodes.tsv"))
  if (file.exists(electrodes_file)) {
    electrodes_df <- utils::read.delim(electrodes_file, stringsAsFactors = FALSE)
    pe <- .applyBIDSElectrodes(pe, electrodes_df)
  }

  # Add BIDS metadata
  meta <- S4Vectors::metadata(pe)
  meta$bids <- list(
    subject = subject,
    session = session,
    task = task,
    run = run,
    modality = modality,
    bids_root = bids_root
  )
  S4Vectors::metadata(pe) <- meta

  pe
}

#' Apply BIDS channel info to PhysioExperiment
#' @noRd
.applyBIDSChannelInfo <- function(pe, channels_df) {
  ch_info <- channelInfo(pe)
  ch_names <- channelNames(pe)

  # Match channels by name
  for (i in seq_len(nrow(channels_df))) {
    ch_name <- channels_df$name[i]
    idx <- match(ch_name, ch_names)

    if (!is.na(idx)) {
      if ("type" %in% names(channels_df)) {
        ch_info$type[idx] <- channels_df$type[i]
      }
      if ("units" %in% names(channels_df)) {
        ch_info$unit[idx] <- channels_df$units[i]
      }
      if ("sampling_frequency" %in% names(channels_df)) {
        ch_info$sampling_rate[idx] <- channels_df$sampling_frequency[i]
      }
      if ("reference" %in% names(channels_df)) {
        ch_info$reference[idx] <- channels_df$reference[i]
      }
      if ("status" %in% names(channels_df)) {
        ch_info$status[idx] <- channels_df$status[i]
      }
    }
  }

  SummarizedExperiment::colData(pe) <- ch_info
  pe
}

#' Apply BIDS events to PhysioExperiment
#' @noRd
.applyBIDSEvents <- function(pe, events_df) {
  # BIDS events.tsv has columns: onset, duration, trial_type, value, etc.
  if (!"onset" %in% names(events_df)) {
    warning("Events file missing 'onset' column", call. = FALSE)
    return(pe)
  }

  onset <- events_df$onset
  duration <- if ("duration" %in% names(events_df)) events_df$duration else 0
  type <- if ("trial_type" %in% names(events_df)) events_df$trial_type else "event"
  value <- if ("value" %in% names(events_df)) as.character(events_df$value) else NA

  events <- PhysioEvents(
    onset = onset,
    duration = duration,
    type = type,
    value = value
  )

  setEvents(pe, events)
}

#' Apply BIDS electrode positions
#' @noRd
.applyBIDSElectrodes <- function(pe, electrodes_df) {
  ch_info <- channelInfo(pe)
  ch_names <- channelNames(pe)

  # Add position columns if not present
  if (!"pos_x" %in% names(ch_info)) {
    ch_info$pos_x <- NA_real_
    ch_info$pos_y <- NA_real_
    ch_info$pos_z <- NA_real_
  }

  for (i in seq_len(nrow(electrodes_df))) {
    electrode_name <- electrodes_df$name[i]
    idx <- match(electrode_name, ch_names)

    if (!is.na(idx)) {
      if ("x" %in% names(electrodes_df)) ch_info$pos_x[idx] <- electrodes_df$x[i]
      if ("y" %in% names(electrodes_df)) ch_info$pos_y[idx] <- electrodes_df$y[i]
      if ("z" %in% names(electrodes_df)) ch_info$pos_z[idx] <- electrodes_df$z[i]
    }
  }

  SummarizedExperiment::colData(pe) <- ch_info
  pe
}

#' Write PhysioExperiment to BIDS format
#'
#' Writes data in BIDS-compliant directory structure.
#'
#' @param x A PhysioExperiment object.
#' @param bids_root Path to the BIDS dataset root directory.
#' @param subject Subject identifier (without 'sub-' prefix).
#' @param session Session identifier (without 'ses-' prefix). Optional.
#' @param task Task name.
#' @param run Run number. Optional.
#' @param modality Data modality: "eeg" or "ieeg".
#' @param overwrite If TRUE, overwrites existing files.
#' @return Invisible path to the created files.
#' @references
#'   Gorgolewski KJ, et al. (2016). "The brain imaging data structure,
#'   a format for organizing and describing outputs of neuroimaging
#'   experiments." Scientific Data, 3, 160044.
#'   doi:10.1038/sdata.2016.44
#' @seealso \code{\link{readBIDS}}, \code{\link{writeEDF}},
#'   \code{\link{listBIDSSubjects}}, \code{\link{validateBIDS}}
#' @export
#' @examples
#' # Create a PhysioExperiment
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
#'   colData = S4Vectors::DataFrame(label = paste0("Ch", 1:10)),
#'   samplingRate = 100
#' )
#'
#' # Export to a BIDS dataset in a temporary directory
#' bids_root <- file.path(tempdir(), "bids-write-demo")
#' writeBIDS(pe, bids_root, subject = "01", task = "rest")
#'
#' unlink(bids_root, recursive = TRUE)
writeBIDS <- function(x, bids_root, subject, session = NULL, task,
                      run = NULL, modality = c("eeg", "ieeg"),
                      overwrite = FALSE) {
  stopifnot(inherits(x, "PhysioExperiment"))
  modality <- match.arg(modality)

  # Create directory structure
  subj_dir <- paste0("sub-", subject)
  path_parts <- c(bids_root, subj_dir)

  if (!is.null(session)) {
    path_parts <- c(path_parts, paste0("ses-", session))
  }
  path_parts <- c(path_parts, modality)

  data_dir <- do.call(file.path, as.list(path_parts))

  if (!dir.exists(data_dir)) {
    dir.create(data_dir, recursive = TRUE)
  }

  # Build filename base
  filename_base <- paste0("sub-", subject)
  if (!is.null(session)) {
    filename_base <- paste0(filename_base, "_ses-", session)
  }
  filename_base <- paste0(filename_base, "_task-", task)
  if (!is.null(run)) {
    filename_base <- paste0(filename_base, "_run-", sprintf("%02d", run))
  }
  filename_base <- paste0(filename_base, "_", modality)

  # Write EDF file
  edf_file <- file.path(data_dir, paste0(filename_base, ".edf"))
  if (file.exists(edf_file) && !overwrite) {
    stop("File exists: ", edf_file, ". Use overwrite = TRUE to replace.", call. = FALSE)
  }
  writeEDF(x, edf_file)

  # Write channels.tsv
  .writeBIDSChannels(x, file.path(data_dir, paste0(filename_base, "_channels.tsv")))

  # Write events.tsv if events present
  events <- getEvents(x)
  if (nEvents(events) > 0) {
    .writeBIDSEvents(events, file.path(data_dir, paste0(filename_base, "_events.tsv")))
  }

  # Write electrodes.tsv if positions available
  .writeBIDSElectrodes(x, file.path(data_dir, paste0(filename_base, "_electrodes.tsv")))

  # Write sidecar JSON
  .writeBIDSSidecar(x, task, file.path(data_dir, paste0(filename_base, ".json")))

  # Bundle a W3C PROV-JSON provenance sidecar (no-op if no provenance)
  .writeProvSidecar(x, file.path(data_dir, paste0(filename_base, "_prov")))

  # Create/update dataset_description.json if it doesn't exist
  desc_file <- file.path(bids_root, "dataset_description.json")
  if (!file.exists(desc_file)) {
    .writeBIDSDescription(bids_root)
  }

  invisible(data_dir)
}

#' Write BIDS channels.tsv
#' @noRd
.writeBIDSChannels <- function(x, filepath) {
  ch_info <- channelInfo(x)
  ch_names <- channelNames(x)
  sr <- samplingRate(x)

  channels_df <- data.frame(
    name = ch_names,
    type = if ("type" %in% names(ch_info)) ch_info$type else "EEG",
    units = if ("unit" %in% names(ch_info)) ch_info$unit else "uV",
    sampling_frequency = sr,
    reference = if ("reference" %in% names(ch_info)) ch_info$reference else NA,
    status = if ("status" %in% names(ch_info)) ch_info$status else "good",
    stringsAsFactors = FALSE
  )

  utils::write.table(channels_df, filepath, sep = "\t", row.names = FALSE,
                     quote = FALSE, na = "n/a")
}

#' Write BIDS events.tsv
#' @noRd
.writeBIDSEvents <- function(events, filepath) {
  event_df <- events@events

  bids_events <- data.frame(
    onset = event_df$onset,
    duration = event_df$duration,
    trial_type = event_df$type,
    value = event_df$value,
    stringsAsFactors = FALSE
  )

  # Replace NA with "n/a" for BIDS compliance
  bids_events[is.na(bids_events)] <- "n/a"

  utils::write.table(bids_events, filepath, sep = "\t", row.names = FALSE,
                     quote = FALSE)
}

#' Write BIDS electrodes.tsv
#' @noRd
.writeBIDSElectrodes <- function(x, filepath) {
  ch_info <- channelInfo(x)
  ch_names <- channelNames(x)

  # Check if we have position data
  has_positions <- all(c("pos_x", "pos_y", "pos_z") %in% names(ch_info)) &&
    any(!is.na(ch_info$pos_x))

  if (!has_positions) {
    return(invisible(NULL))
  }

  electrodes_df <- data.frame(
    name = ch_names,
    x = if ("pos_x" %in% names(ch_info)) ch_info$pos_x else NA,
    y = if ("pos_y" %in% names(ch_info)) ch_info$pos_y else NA,
    z = if ("pos_z" %in% names(ch_info)) ch_info$pos_z else NA,
    stringsAsFactors = FALSE
  )

  # Filter out channels without positions
  electrodes_df <- electrodes_df[!is.na(electrodes_df$x), ]

  if (nrow(electrodes_df) > 0) {
    electrodes_df[is.na(electrodes_df)] <- "n/a"
    utils::write.table(electrodes_df, filepath, sep = "\t", row.names = FALSE,
                       quote = FALSE)
  }
}

#' Write BIDS sidecar JSON
#' @noRd
.writeBIDSSidecar <- function(x, task, filepath) {
  sr <- samplingRate(x)
  meta <- S4Vectors::metadata(x)

  sidecar <- list(
    TaskName = task,
    SamplingFrequency = sr,
    PowerLineFrequency = if (!is.null(meta$powerline_frequency)) meta$powerline_frequency else 50,
    SoftwareFilters = "n/a",
    RecordingType = "continuous"
  )

  # Add EEG-specific fields
  if (!is.null(meta$reference)) {
    sidecar$EEGReference <- meta$reference
  }

  json_str <- jsonlite::toJSON(sidecar, auto_unbox = TRUE, pretty = TRUE)
  writeLines(json_str, filepath)
}

#' Write BIDS dataset description
#' @noRd
.writeBIDSDescription <- function(bids_root, generated_by = NULL,
                                  dataset_type = "raw", name = NULL) {
  if (is.null(generated_by)) {
    generated_by <- list(list(
      Name = "PhysioIO",
      Version = as.character(utils::packageVersion("PhysioIO"))))
  }
  desc <- list(
    Name = if (is.null(name)) basename(bids_root) else name,
    BIDSVersion = "1.9.0",
    DatasetType = dataset_type,
    GeneratedBy = generated_by
  )

  json_str <- jsonlite::toJSON(desc, auto_unbox = TRUE, pretty = TRUE)
  writeLines(json_str, file.path(bids_root, "dataset_description.json"))
}

#' List subjects in a BIDS dataset
#'
#' @param bids_root Path to the BIDS dataset root.
#' @return Character vector of subject IDs (without 'sub-' prefix).
#' @references
#'   Gorgolewski KJ, et al. (2016). "The brain imaging data structure,
#'   a format for organizing and describing outputs of neuroimaging
#'   experiments." Scientific Data, 3, 160044.
#'   doi:10.1038/sdata.2016.44
#' @seealso \code{\link{listBIDSSessions}}, \code{\link{readBIDS}},
#'   \code{\link{validateBIDS}}
#' @export
#' @examples
#' # Write a minimal BIDS dataset, then list its subjects
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
#'   colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
#'   samplingRate = 100
#' )
#' bids_root <- file.path(tempdir(), "bids-list-demo")
#' writeBIDS(pe, bids_root, subject = "01", task = "rest")
#'
#' listBIDSSubjects(bids_root)
#' unlink(bids_root, recursive = TRUE)
listBIDSSubjects <- function(bids_root) {
  if (!dir.exists(bids_root)) {
    stop("BIDS root directory not found: ", bids_root, call. = FALSE)
  }

  dirs <- list.dirs(bids_root, recursive = FALSE, full.names = FALSE)
  subj_dirs <- dirs[grepl("^sub-", dirs)]
  sub("^sub-", "", subj_dirs)
}

#' List sessions for a subject in BIDS dataset
#'
#' @param bids_root Path to the BIDS dataset root.
#' @param subject Subject identifier (without 'sub-' prefix).
#' @return Character vector of session IDs (without 'ses-' prefix).
#' @references
#'   Gorgolewski KJ, et al. (2016). "The brain imaging data structure,
#'   a format for organizing and describing outputs of neuroimaging
#'   experiments." Scientific Data, 3, 160044.
#'   doi:10.1038/sdata.2016.44
#' @seealso \code{\link{listBIDSSubjects}}, \code{\link{readBIDS}},
#'   \code{\link{validateBIDS}}
#' @export
#' @examples
#' # Write a BIDS dataset with a session, then list sessions for the subject
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
#'   colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
#'   samplingRate = 100
#' )
#' bids_root <- file.path(tempdir(), "bids-session-demo")
#' writeBIDS(pe, bids_root, subject = "01", session = "baseline", task = "rest")
#'
#' listBIDSSessions(bids_root, subject = "01")
#' unlink(bids_root, recursive = TRUE)
listBIDSSessions <- function(bids_root, subject) {
  subj_dir <- file.path(bids_root, paste0("sub-", subject))

  if (!dir.exists(subj_dir)) {
    stop("Subject directory not found: ", subj_dir, call. = FALSE)
  }

  dirs <- list.dirs(subj_dir, recursive = FALSE, full.names = FALSE)
  ses_dirs <- dirs[grepl("^ses-", dirs)]
  sub("^ses-", "", ses_dirs)
}

#' Validate BIDS dataset structure
#'
#' Performs basic validation of BIDS compliance.
#'
#' @param bids_root Path to the BIDS dataset root.
#' @return A list with validation results.
#' @references
#'   Gorgolewski KJ, et al. (2016). "The brain imaging data structure,
#'   a format for organizing and describing outputs of neuroimaging
#'   experiments." Scientific Data, 3, 160044.
#'   doi:10.1038/sdata.2016.44
#' @seealso \code{\link{readBIDS}}, \code{\link{writeBIDS}},
#'   \code{\link{listBIDSSubjects}}
#' @export
#' @examples
#' # Write a minimal BIDS dataset, then validate it
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
#'   colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
#'   samplingRate = 100
#' )
#' bids_root <- file.path(tempdir(), "bids-validate-demo")
#' writeBIDS(pe, bids_root, subject = "01", task = "rest")
#'
#' result <- validateBIDS(bids_root)
#' result$valid
#'
#' unlink(bids_root, recursive = TRUE)
validateBIDS <- function(bids_root) {
  errors <- character()
  warnings <- character()

  if (!dir.exists(bids_root)) {
    return(list(valid = FALSE, errors = "BIDS root directory not found", warnings = character()))
  }

  # Check for dataset_description.json
  desc_file <- file.path(bids_root, "dataset_description.json")
  if (!file.exists(desc_file)) {
    errors <- c(errors, "Missing dataset_description.json")
  } else {
    desc <- tryCatch(
      jsonlite::fromJSON(desc_file),
      error = function(e) NULL
    )
    if (is.null(desc)) {
      errors <- c(errors, "Invalid JSON in dataset_description.json")
    } else {
      if (is.null(desc$Name)) {
        errors <- c(errors, "dataset_description.json missing 'Name' field")
      }
      if (is.null(desc$BIDSVersion)) {
        warnings <- c(warnings, "dataset_description.json missing 'BIDSVersion' field")
      }
    }
  }

  # Check for subject directories
  dirs <- list.dirs(bids_root, recursive = FALSE, full.names = FALSE)
  subj_dirs <- dirs[grepl("^sub-", dirs)]

  if (length(subj_dirs) == 0) {
    warnings <- c(warnings, "No subject directories found")
  }

  # Check each subject
  for (subj in subj_dirs) {
    subj_path <- file.path(bids_root, subj)

    # Look for modality directories
    modalities <- c("eeg", "ieeg", "meg", "beh", "motion")
    has_modality <- FALSE

    subdirs <- list.dirs(subj_path, recursive = TRUE, full.names = FALSE)
    for (mod in modalities) {
      if (mod %in% subdirs || any(grepl(paste0("/", mod, "$"), subdirs))) {
        has_modality <- TRUE
        break
      }
    }

    if (!has_modality) {
      # Check for session directories
      ses_dirs <- list.dirs(subj_path, recursive = FALSE, full.names = FALSE)
      ses_dirs <- ses_dirs[grepl("^ses-", ses_dirs)]
      if (length(ses_dirs) == 0) {
        warnings <- c(warnings, paste0(subj, ": No modality or session directories found"))
      }
    }
  }

  list(
    valid = length(errors) == 0,
    errors = errors,
    warnings = warnings,
    n_subjects = length(subj_dirs)
  )
}
