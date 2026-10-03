#' CSV/TSV I/O for PhysioExperiment
#'
#' Functions for reading and writing signal data in CSV/TSV format.
#' Supports both wide format (time x channels) and long format.

#' Read PhysioExperiment from CSV file
#'
#' Reads physiological signal data from a CSV file.
#'
#' @param path Path to the CSV file.
#' @param format Data format: "wide" (time x channels) or "long" (stacked).
#' @param time_col Name of the time column. If NULL, assumes first column or
#'   generates time from sampling rate.
#' @param channel_cols For wide format, column names/indices to use as channels.
#'   If NULL, uses all non-time columns.
#' @param sampling_rate Sampling rate in Hz. Required if time column is not present.
#' @param sep Column separator. Default is ",".
#' @param header Logical. If TRUE, first row contains column names.
#' @param ... Additional arguments passed to read.csv/read.table.
#' @return A PhysioExperiment object.
#' @references
#'   Wickham H (2014). "Tidy Data." Journal of Statistical Software,
#'   59(10), 1-23. doi:10.18637/jss.v059.i10
#' @seealso \code{\link{writeCSV}}, \code{\link{readEventsCSV}},
#'   \code{\link{readEDF}}, \code{\link{readMAT}}
#' @export
#' @examples
#' # Write a wide-format CSV, then read it back
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
#'   colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
#'   samplingRate = 100
#' )
#' tmp <- tempfile(fileext = ".csv")
#' writeCSV(pe, tmp)
#'
#' # Read using the written time column
#' pe_in <- readCSV(tmp, time_col = "time")
#'
#' # Read without a time column (generate time from sampling rate)
#' pe_sr <- readCSV(tmp, channel_cols = c("Fz", "Cz", "Pz", "Oz"),
#'                  sampling_rate = 100)
#'
#' unlink(tmp)
readCSV <- function(path, format = c("wide", "long"), time_col = NULL,
                    channel_cols = NULL, sampling_rate = NULL,
                    sep = ",", header = TRUE, ...) {
  format <- match.arg(format)

  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  # Read the data
  data <- utils::read.csv(path, sep = sep, header = header,
                          stringsAsFactors = FALSE, ...)

  if (nrow(data) == 0) {
    stop("CSV file is empty", call. = FALSE)
  }

  if (format == "wide") {
    .readCSVWide(data, time_col, channel_cols, sampling_rate)
  } else {
    .readCSVLong(data, time_col, sampling_rate)
  }
}

#' Internal: Read wide-format CSV
#' @noRd
.readCSVWide <- function(data, time_col, channel_cols, sampling_rate) {
  # Identify time column
  if (!is.null(time_col)) {
    if (is.character(time_col)) {
      if (!time_col %in% names(data)) {
        stop("Time column '", time_col, "' not found", call. = FALSE)
      }
      time_idx <- which(names(data) == time_col)
    } else {
      time_idx <- time_col
    }
    time_vec <- data[[time_idx]]
    data_cols <- setdiff(seq_len(ncol(data)), time_idx)
  } else {
    time_vec <- NULL
    data_cols <- seq_len(ncol(data))
  }

  # Identify channel columns
  if (!is.null(channel_cols)) {
    if (is.character(channel_cols)) {
      ch_idx <- match(channel_cols, names(data))
      if (any(is.na(ch_idx))) {
        missing <- channel_cols[is.na(ch_idx)]
        stop("Channels not found: ", paste(missing, collapse = ", "), call. = FALSE)
      }
    } else {
      ch_idx <- channel_cols
    }
  } else {
    ch_idx <- data_cols
  }

  # Extract signal matrix
  signal_matrix <- as.matrix(data[, ch_idx, drop = FALSE])
  mode(signal_matrix) <- "numeric"
  ch_names <- names(data)[ch_idx]

  n_samples <- nrow(signal_matrix)
  n_channels <- ncol(signal_matrix)

  # Determine sampling rate
  if (is.null(sampling_rate)) {
    if (!is.null(time_vec) && length(time_vec) >= 2) {
      dt <- mean(diff(time_vec))
      sampling_rate <- 1 / dt
    } else {
      stop("sampling_rate required when time column is not provided", call. = FALSE)
    }
  }

  # Create column data (channel metadata - channels are columns)
  col_data <- S4Vectors::DataFrame(label = ch_names)

  # Create PhysioExperiment
  PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = signal_matrix),
    colData = col_data,
    samplingRate = sampling_rate
  )
}

#' Internal: Read long-format CSV
#' @noRd
.readCSVLong <- function(data, time_col, sampling_rate) {
  # Long format expects: time, channel, value
  required_cols <- c("channel", "value")

  if (!all(required_cols %in% names(data))) {
    stop("Long format requires 'channel' and 'value' columns", call. = FALSE)
  }

  channels <- unique(data$channel)
  n_channels <- length(channels)

  # Split by channel and stack
  channel_list <- split(data, data$channel)

  # Verify all channels have same length
  lengths <- sapply(channel_list, nrow)
  if (length(unique(lengths)) > 1) {
    warning("Channels have different lengths. Using minimum length.", call. = FALSE)
  }
  n_samples <- min(lengths)

  signal_matrix <- matrix(NA_real_, nrow = n_samples, ncol = n_channels)

  for (i in seq_along(channels)) {
    ch_data <- channel_list[[channels[i]]]
    signal_matrix[, i] <- ch_data$value[seq_len(n_samples)]
  }

  # Determine sampling rate
  if (is.null(sampling_rate)) {
    if (!is.null(time_col) && time_col %in% names(data)) {
      first_ch <- channel_list[[1]]
      time_vec <- first_ch[[time_col]]
      if (length(time_vec) >= 2) {
        dt <- mean(diff(time_vec))
        sampling_rate <- 1 / dt
      }
    }
    if (is.null(sampling_rate)) {
      stop("sampling_rate required", call. = FALSE)
    }
  }

  # Create column data (channel metadata - channels are columns)
  col_data <- S4Vectors::DataFrame(label = as.character(channels))

  PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = signal_matrix),
    colData = col_data,
    samplingRate = sampling_rate
  )
}

#' Write PhysioExperiment to CSV file
#'
#' Writes physiological signal data to a CSV file.
#'
#' @param x A PhysioExperiment object.
#' @param path Output file path.
#' @param format Output format: "wide" (time x channels) or "long".
#' @param include_time Logical. If TRUE, includes a time column.
#' @param assay_name Assay to export. If NULL, uses default assay.
#' @param sep Column separator. Default is ",".
#' @param ... Additional arguments passed to write.csv/write.table.
#' @return Invisible path to the created file.
#' @references
#'   Wickham H (2014). "Tidy Data." Journal of Statistical Software,
#'   59(10), 1-23. doi:10.18637/jss.v059.i10
#' @seealso \code{\link{readCSV}}, \code{\link{writeEventsCSV}},
#'   \code{\link{writeEDF}}, \code{\link{writePhysioHDF5}}
#' @export
#' @examples
#' # Create example data
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
#'   colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
#'   samplingRate = 100
#' )
#'
#' # Write to temporary CSV file
#' tmp <- tempfile(fileext = ".csv")
#' writeCSV(pe, tmp)
#'
#' # Write in long format
#' writeCSV(pe, tmp, format = "long")
#'
#' # Clean up
#' unlink(tmp)
writeCSV <- function(x, path, format = c("wide", "long"),
                     include_time = TRUE, assay_name = NULL,
                     sep = ",", ...) {
  stopifnot(inherits(x, "PhysioExperiment"))
  format <- match.arg(format)

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
    dims <- dim(data)
  }

  ch_names <- channelNames(x)
  if (length(ch_names) != dims[2]) {
    ch_names <- paste0("Ch", seq_len(dims[2]))
  }

  sr <- samplingRate(x)
  time_vec <- if (!is.na(sr) && sr > 0) {
    seq(0, (dims[1] - 1) / sr, length.out = dims[1])
  } else {
    seq_len(dims[1])
  }

  if (format == "wide") {
    df <- as.data.frame(data)
    names(df) <- ch_names

    if (include_time) {
      df <- cbind(time = time_vec, df)
    }

    utils::write.table(df, path, sep = sep, row.names = FALSE,
                       col.names = TRUE, quote = TRUE, ...)
  } else {
    # Long format
    long_list <- list()

    for (i in seq_len(dims[2])) {
      long_list[[i]] <- data.frame(
        time = time_vec,
        channel = ch_names[i],
        value = data[, i]
      )
    }

    df <- do.call(rbind, long_list)

    if (!include_time) {
      df$time <- NULL
    }

    utils::write.table(df, path, sep = sep, row.names = FALSE,
                       col.names = TRUE, quote = TRUE, ...)
  }

  invisible(path)
}

#' Read events from CSV/TSV file
#'
#' Reads event markers from a CSV file with onset, duration, and type columns.
#'
#' @param path Path to the CSV file.
#' @param onset_col Name of the onset column (in seconds).
#' @param duration_col Name of the duration column.
#' @param type_col Name of the event type column.
#' @param value_col Name of the event value column.
#' @param sep Column separator.
#' @param ... Additional arguments passed to read.csv.
#' @return A PhysioEvents object.
#' @references
#'   Wickham H (2014). "Tidy Data." Journal of Statistical Software,
#'   59(10), 1-23. doi:10.18637/jss.v059.i10
#' @seealso \code{\link{writeEventsCSV}}, \code{\link{readCSV}},
#'   \code{\link{readBIDS}}
#' @export
#' @examples
#' # Write events to a temporary CSV, then read them back
#' events <- PhysioEvents(
#'   onset = c(1.0, 2.5, 4.0),
#'   duration = c(0.5, 0.5, 0.5),
#'   type = c("stimulus", "stimulus", "response"),
#'   value = c("A", "B", "correct")
#' )
#' tmp <- tempfile(fileext = ".csv")
#' writeEventsCSV(events, tmp)
#'
#' events_in <- readEventsCSV(tmp)
#' unlink(tmp)
readEventsCSV <- function(path, onset_col = "onset", duration_col = "duration",
                          type_col = "type", value_col = "value",
                          sep = ",", ...) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  data <- utils::read.csv(path, sep = sep, stringsAsFactors = FALSE, ...)

  if (!onset_col %in% names(data)) {
    stop("Onset column '", onset_col, "' not found", call. = FALSE)
  }

  onset <- data[[onset_col]]
  duration <- if (duration_col %in% names(data)) data[[duration_col]] else 0
  type <- if (type_col %in% names(data)) data[[type_col]] else "event"
  value <- if (value_col %in% names(data)) as.character(data[[value_col]]) else NA

  PhysioEvents(
    onset = onset,
    duration = duration,
    type = type,
    value = value
  )
}

#' Write events to CSV file
#'
#' Writes PhysioEvents to a CSV file.
#'
#' @param events A PhysioEvents object.
#' @param path Output file path.
#' @param sep Column separator.
#' @param ... Additional arguments passed to write.csv.
#' @return Invisible path to the created file.
#' @references
#'   Wickham H (2014). "Tidy Data." Journal of Statistical Software,
#'   59(10), 1-23. doi:10.18637/jss.v059.i10
#' @seealso \code{\link{readEventsCSV}}, \code{\link{writeCSV}},
#'   \code{\link{writeBIDS}}
#' @export
#' @examples
#' # Create events
#' events <- PhysioEvents(
#'   onset = c(1.0, 2.5, 4.0),
#'   duration = c(0.5, 0.5, 0.5),
#'   type = c("stimulus", "stimulus", "response"),
#'   value = c("A", "B", "correct")
#' )
#'
#' # Write to temporary file
#' tmp <- tempfile(fileext = ".csv")
#' writeEventsCSV(events, tmp)
#'
#' # Clean up
#' unlink(tmp)
writeEventsCSV <- function(events, path, sep = ",", ...) {
  stopifnot(inherits(events, "PhysioEvents"))

  df <- events@events

  utils::write.table(df, path, sep = sep, row.names = FALSE,
                     col.names = TRUE, quote = TRUE, ...)

  invisible(path)
}

#' Read electrode positions from CSV
#'
#' Reads electrode positions from a CSV file with x, y, z coordinates.
#'
#' @param path Path to the CSV file.
#' @param name_col Name of the electrode name column.
#' @param x_col Name of the x coordinate column.
#' @param y_col Name of the y coordinate column.
#' @param z_col Name of the z coordinate column.
#' @param sep Column separator.
#' @param ... Additional arguments passed to read.csv.
#' @return A data.frame with electrode positions.
#' @references
#'   Wickham H (2014). "Tidy Data." Journal of Statistical Software,
#'   59(10), 1-23. doi:10.18637/jss.v059.i10
#' @seealso \code{\link{writeElectrodePositionsCSV}}, \code{\link{readCSV}},
#'   \code{\link{readBIDS}}
#' @export
#' @examples
#' # Write electrode positions to a temporary CSV, then read them back
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
#'   colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
#'   samplingRate = 100
#' )
#' pe <- applyMontage(pe, "10-20")
#' tmp <- tempfile(fileext = ".csv")
#' writeElectrodePositionsCSV(pe, tmp)
#'
#' positions <- readElectrodePositionsCSV(tmp)
#' unlink(tmp)
readElectrodePositionsCSV <- function(path, name_col = "name",
                                       x_col = "x", y_col = "y", z_col = "z",
                                       sep = ",", ...) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  data <- utils::read.csv(path, sep = sep, stringsAsFactors = FALSE, ...)

  required_cols <- c(x_col, y_col, z_col)
  if (!all(required_cols %in% names(data))) {
    missing <- required_cols[!required_cols %in% names(data)]
    stop("Columns not found: ", paste(missing, collapse = ", "), call. = FALSE)
  }

  result <- data.frame(
    x = data[[x_col]],
    y = data[[y_col]],
    z = data[[z_col]]
  )

  if (name_col %in% names(data)) {
    result$name <- data[[name_col]]
  }

  result
}

#' Write electrode positions to CSV
#'
#' Writes electrode positions from a PhysioExperiment to CSV.
#'
#' @param x A PhysioExperiment object with electrode positions.
#' @param path Output file path.
#' @param sep Column separator.
#' @param ... Additional arguments passed to write.csv.
#' @return Invisible path to the created file.
#' @references
#'   Wickham H (2014). "Tidy Data." Journal of Statistical Software,
#'   59(10), 1-23. doi:10.18637/jss.v059.i10
#' @seealso \code{\link{readElectrodePositionsCSV}}, \code{\link{writeCSV}},
#'   \code{\link{writeBIDS}}
#' @export
#' @examples
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
#'   colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
#'   samplingRate = 100
#' )
#' pe <- applyMontage(pe, "10-20")
#'
#' # Write electrode positions
#' tmp <- tempfile(fileext = ".csv")
#' writeElectrodePositionsCSV(pe, tmp)
#'
#' # Clean up
#' unlink(tmp)
writeElectrodePositionsCSV <- function(x, path, sep = ",", ...) {
  stopifnot(inherits(x, "PhysioExperiment"))

  positions <- getElectrodePositions(x)

  if (is.null(positions)) {
    stop("No electrode positions set", call. = FALSE)
  }

  utils::write.table(positions, path, sep = sep, row.names = FALSE,
                     col.names = TRUE, quote = TRUE, ...)

  invisible(path)
}
