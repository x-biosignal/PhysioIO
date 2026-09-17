#' MATLAB .mat File I/O for PhysioExperiment
#'
#' Functions for reading and writing MATLAB .mat files.
#' Requires the R.matlab package.

#' Internal: get readMat backend function
#' @noRd
.getReadMatBackend <- function() {
  backend <- getOption("PhysioIO.readMatFun", NULL)
  if (is.function(backend)) {
    return(backend)
  }

  if (!requireNamespace("R.matlab", quietly = TRUE)) {
    stop("Package 'R.matlab' required for reading .mat files. ",
         "Install with: install.packages('R.matlab')", call. = FALSE)
  }

  function(path) R.matlab::readMat(path)
}

#' Internal: get writeMat backend function
#' @noRd
.getWriteMatBackend <- function() {
  backend <- getOption("PhysioIO.writeMatFun", NULL)
  if (is.function(backend)) {
    return(backend)
  }

  if (!requireNamespace("R.matlab", quietly = TRUE)) {
    stop("Package 'R.matlab' required for writing .mat files. ",
         "Install with: install.packages('R.matlab')", call. = FALSE)
  }

  function(path, export_list) do.call(R.matlab::writeMat, c(list(con = path), export_list))
}

#' Read PhysioExperiment from MATLAB .mat file
#'
#' Reads physiological signal data from a MATLAB .mat file.
#' Supports both standard .mat files and EEGLAB .set structures.
#'
#' @param path Path to the .mat file.
#' @param data_var Name of the variable containing signal data.
#'   If NULL, attempts to auto-detect.
#' @param sr_var Name of the variable containing sampling rate.
#' @param channel_var Name of the variable containing channel labels.
#' @param event_var Name of the variable containing events.
#' @param transpose Logical. If TRUE, transposes the data matrix.
#' @return A PhysioExperiment object.
#' @details
#' The function attempts to auto-detect the data structure if variable names
#' are not specified. It looks for common variable names used in EEG toolboxes:
#' - data, EEG.data, signal, X for signal data
#' - srate, fs, Fs, samplingRate for sampling rate
#' - chanlocs, channels, labels for channel information
#' - event, events, EEG.event for events
#' @references
#'   MathWorks (2024). "MAT-File Format." Technical documentation.
#'   \url{https://www.mathworks.com/help/matlab/import_export/mat-file-versions.html}
#' @seealso \code{\link{writeMAT}}, \code{\link{readEDF}},
#'   \code{\link{readCSV}}, \code{\link{readPhysioHDF5}}
#' @export
#' @examples
#' # 'R.matlab' is an optional dependency; guard the round-trip example so it
#' # only runs when the package is installed.
#' if (requireNamespace("R.matlab", quietly = TRUE)) {
#'   pe <- PhysioExperiment(
#'     assays = list(raw = matrix(0, nrow = 100, ncol = 3)),
#'     colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz")),
#'     samplingRate = 256
#'   )
#'   tf <- tempfile(fileext = ".mat")
#'   writeMAT(pe, tf)
#'   pe2 <- readMAT(tf)
#'   unlink(tf)
#' }
readMAT <- function(path, data_var = NULL, sr_var = NULL,
                    channel_var = NULL, event_var = NULL,
                    transpose = FALSE) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  # Read the .mat file
  read_mat <- .getReadMatBackend()
  mat <- read_mat(path)

  # Auto-detect data variable
  if (is.null(data_var)) {
    data_var <- .detectMatDataVar(mat)
  }

  if (is.null(data_var) || !data_var %in% names(mat)) {
    stop("Could not find data variable. Available variables: ",
         paste(names(mat), collapse = ", "), call. = FALSE)
  }

  # Extract data
  data_content <- mat[[data_var]]

  # Handle EEGLAB structure
  if (is.list(data_content) && "data" %in% names(data_content[[1]])) {
    eeg_struct <- data_content[[1]]
    signal_data <- eeg_struct$data[[1]]

    if (is.null(sr_var) && "srate" %in% names(eeg_struct)) {
      sampling_rate <- as.numeric(eeg_struct$srate[[1]])
    }

    if (is.null(channel_var) && "chanlocs" %in% names(eeg_struct)) {
      ch_info <- .parseEEGLABChanlocs(eeg_struct$chanlocs)
    }

    if (is.null(event_var) && "event" %in% names(eeg_struct)) {
      events <- .parseEEGLABEvents(eeg_struct$event)
    }
  } else {
    signal_data <- as.matrix(data_content)
  }

  # Ensure numeric
  mode(signal_data) <- "numeric"

  # Transpose if needed (MATLAB typically stores channels x samples)
  if (transpose || ncol(signal_data) > nrow(signal_data) * 10) {
    signal_data <- t(signal_data)
  }

  n_samples <- nrow(signal_data)
  n_channels <- ncol(signal_data)

  # Get sampling rate
  if (!exists("sampling_rate", inherits = FALSE)) {
    sampling_rate <- NULL
    if (!is.null(sr_var) && sr_var %in% names(mat)) {
      sampling_rate <- as.numeric(mat[[sr_var]])
    } else {
      sr_candidates <- c("srate", "fs", "Fs", "samplingRate", "sr", "SampleRate")
      for (cand in sr_candidates) {
        if (cand %in% names(mat)) {
          sampling_rate <- as.numeric(mat[[cand]])
          break
        }
      }
    }
  }

  if (is.null(sampling_rate) || is.na(sampling_rate)) {
    warning("Sampling rate not found. Setting to 1 Hz.", call. = FALSE)
    sampling_rate <- 1
  }

  # Get channel information
  if (!exists("ch_info", inherits = FALSE)) {
    ch_info <- NULL
    if (!is.null(channel_var) && channel_var %in% names(mat)) {
      ch_data <- mat[[channel_var]]
      if (is.character(ch_data)) {
        ch_info <- S4Vectors::DataFrame(label = ch_data)
      } else if (is.list(ch_data)) {
        labels <- sapply(ch_data, function(x) {
          if (is.list(x) && "labels" %in% names(x)) x$labels else as.character(x)
        })
        ch_info <- S4Vectors::DataFrame(label = labels)
      }
    }
  }

  if (is.null(ch_info)) {
    ch_info <- S4Vectors::DataFrame(label = paste0("Ch", seq_len(n_channels)))
  }

  # Create PhysioExperiment (channels are columns, so use colData)
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = signal_data),
    colData = ch_info,
    samplingRate = sampling_rate
  )

  # Add events if found
  if (exists("events", inherits = FALSE) && !is.null(events)) {
    pe <- setEvents(pe, events)
  }

  pe
}

#' Write PhysioExperiment to MATLAB .mat file
#'
#' Saves a PhysioExperiment object to MATLAB .mat format.
#'
#' @param x A PhysioExperiment object.
#' @param path Output file path.
#' @param data_var Name for the data variable in the .mat file.
#' @param include_metadata Logical. If TRUE, includes metadata variables.
#' @param eeglab Logical. If TRUE, exports in EEGLAB-compatible structure.
#' @param assay_name Assay to export. If NULL, uses default assay.
#' @return Invisible NULL.
#' @references
#'   MathWorks (2024). "MAT-File Format." Technical documentation.
#'   \url{https://www.mathworks.com/help/matlab/import_export/mat-file-versions.html}
#' @seealso \code{\link{readMAT}}, \code{\link{writeCSV}},
#'   \code{\link{writeEDF}}, \code{\link{writePhysioHDF5}}
#' @export
#' @examples
#' # 'R.matlab' is an optional dependency; guard the example so it only runs
#' # when the package is installed.
#' if (requireNamespace("R.matlab", quietly = TRUE)) {
#'   pe <- PhysioExperiment(
#'     assays = list(raw = matrix(0, nrow = 100, ncol = 10)),
#'     colData = S4Vectors::DataFrame(label = paste0("Ch", seq_len(10))),
#'     samplingRate = 256
#'   )
#'   tf <- tempfile(fileext = ".mat")
#'   writeMAT(pe, tf)
#'   unlink(tf)
#' }
writeMAT <- function(x, path, data_var = "data",
                     include_metadata = TRUE, eeglab = FALSE,
                     assay_name = NULL) {
  stopifnot(inherits(x, "PhysioExperiment"))

  if (is.null(assay_name)) {
    assay_name <- defaultAssay(x)
  }

  if (is.na(assay_name)) {
    stop("No assays available for export", call. = FALSE)
  }

  data <- SummarizedExperiment::assay(x, assay_name)
  dims <- dim(data)

  # Flatten to 2D if needed
  if (length(dims) > 2) {
    data <- data[, , 1]
  }

  # Transpose to MATLAB convention (channels x samples)
  data <- t(data)

  write_mat <- .getWriteMatBackend()

  if (eeglab) {
    # Create EEGLAB-compatible structure
    eeg_struct <- list(
      data = data,
      srate = samplingRate(x),
      nbchan = nChannels(x),
      pnts = dims[1],
      trials = 1L,
      xmin = 0,
      xmax = (dims[1] - 1) / samplingRate(x)
    )

    # Add channel labels
    ch_names <- channelNames(x)
    chanlocs <- lapply(seq_along(ch_names), function(i) {
      list(labels = ch_names[i])
    })
    eeg_struct$chanlocs <- chanlocs

    # Add events if present
    events <- getEvents(x)
    if (nEvents(events) > 0) {
      event_df <- events@events
      eeg_events <- lapply(seq_len(nrow(event_df)), function(i) {
        list(
          type = event_df$type[i],
          latency = event_df$onset[i] * samplingRate(x),
          duration = event_df$duration[i] * samplingRate(x)
        )
      })
      eeg_struct$event <- eeg_events
    }

    export_list <- list(EEG = eeg_struct)
    write_mat(path, export_list)
  } else {
    # Build export list
    export_list <- list()
    export_list[[data_var]] <- data

    if (include_metadata) {
      export_list[["srate"]] <- samplingRate(x)
      export_list[["channels"]] <- channelNames(x)
      export_list[["nchans"]] <- nChannels(x)
      export_list[["nsamples"]] <- dims[1]

      # Add events if present
      events <- getEvents(x)
      if (nEvents(events) > 0) {
        event_df <- events@events
        export_list[["event_onset"]] <- event_df$onset
        export_list[["event_duration"]] <- event_df$duration
        export_list[["event_type"]] <- event_df$type
      }
    }

    write_mat(path, export_list)
  }

  invisible(NULL)
}

#' Internal: Detect data variable in .mat file
#' @noRd
.detectMatDataVar <- function(mat) {
  # Common data variable names
  candidates <- c("data", "EEG", "signal", "X", "eeg", "Signal",
                  "raw", "signals", "Data")

  for (cand in candidates) {
    if (cand %in% names(mat)) {
      val <- mat[[cand]]
      # Check if it looks like signal data
      if (is.matrix(val) || is.array(val) ||
          (is.list(val) && length(val) > 0)) {
        return(cand)
      }
    }
  }

  # Fall back to first numeric matrix
  for (name in names(mat)) {
    val <- mat[[name]]
    if (is.matrix(val) && is.numeric(val)) {
      return(name)
    }
  }

  NULL
}

#' Internal: Parse EEGLAB chanlocs structure
#' @noRd
.parseEEGLABChanlocs <- function(chanlocs) {
  if (is.null(chanlocs) || length(chanlocs) == 0) {
    return(NULL)
  }

  n_channels <- length(chanlocs[[1]])
  labels <- character(n_channels)
  pos_x <- numeric(n_channels)
  pos_y <- numeric(n_channels)
  pos_z <- numeric(n_channels)

  for (i in seq_len(n_channels)) {
    ch <- chanlocs[[1]][[i]]

    if ("labels" %in% names(ch)) {
      labels[i] <- as.character(ch$labels)
    } else {
      labels[i] <- paste0("Ch", i)
    }

    if ("X" %in% names(ch)) pos_x[i] <- as.numeric(ch$X) else pos_x[i] <- NA
    if ("Y" %in% names(ch)) pos_y[i] <- as.numeric(ch$Y) else pos_y[i] <- NA
    if ("Z" %in% names(ch)) pos_z[i] <- as.numeric(ch$Z) else pos_z[i] <- NA
  }

  S4Vectors::DataFrame(
    label = labels,
    pos_x = pos_x,
    pos_y = pos_y,
    pos_z = pos_z
  )
}

#' Internal: Parse EEGLAB event structure
#' @noRd
.parseEEGLABEvents <- function(event_struct) {
  if (is.null(event_struct) || length(event_struct) == 0) {
    return(NULL)
  }

  events <- event_struct[[1]]
  n_events <- length(events)

  if (n_events == 0) {
    return(NULL)
  }

  onset <- numeric(n_events)
  duration <- numeric(n_events)
  type <- character(n_events)
  value <- character(n_events)

  for (i in seq_len(n_events)) {
    evt <- events[[i]]

    if ("latency" %in% names(evt)) {
      onset[i] <- as.numeric(evt$latency)
    } else {
      onset[i] <- NA
    }

    if ("duration" %in% names(evt)) {
      duration[i] <- as.numeric(evt$duration)
    } else {
      duration[i] <- 0
    }

    if ("type" %in% names(evt)) {
      type[i] <- as.character(evt$type)
    } else {
      type[i] <- "event"
    }

    if ("value" %in% names(evt)) {
      value[i] <- as.character(evt$value)
    } else {
      value[i] <- NA
    }
  }

  # Remove NA onsets
  valid <- !is.na(onset)
  if (!any(valid)) {
    return(NULL)
  }

  PhysioEvents(
    onset = onset[valid],
    duration = duration[valid],
    type = type[valid],
    value = value[valid]
  )
}
