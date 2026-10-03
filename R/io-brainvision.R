#' BrainVision File Format I/O for PhysioExperiment
#'
#' Functions for reading and writing BrainVision format files (.vhdr/.vmrk/.eeg).
#' BrainVision is one of the official BIDS-EEG formats and is widely supported
#' by EEG analysis software (MNE-Python, EEGLAB, FieldTrip, etc.).

#' Read PhysioExperiment from BrainVision files
#'
#' Reads EEG data from BrainVision format files. The format consists of three files:
#' a header file (.vhdr), a marker file (.vmrk), and a binary data file (.eeg).
#'
#' @param path Path to the .vhdr header file.
#' @param channels Optional character vector of channel names to load.
#'   If NULL, loads all channels.
#' @return A PhysioExperiment object.
#' @export
#' @examples
#' # Round-trip a small recording through temporary BrainVision files
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
#'   colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
#'   samplingRate = 100
#' )
#' base <- tempfile()
#' writeBrainVision(pe, base)
#'
#' pe_in <- readBrainVision(paste0(base, ".vhdr"))
#' dim(SummarizedExperiment::assay(pe_in, "raw"))
#'
#' unlink(paste0(base, c(".vhdr", ".vmrk", ".eeg")))
readBrainVision <- function(path, channels = NULL) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  # Ensure path has .vhdr extension
 if (!grepl("\\.vhdr$", path, ignore.case = TRUE)) {
    stop("Path must be a .vhdr header file", call. = FALSE)
  }

  # Parse header file
  header <- .parseBrainVisionHeader(path)

  # Determine data file path
  base_path <- sub("\\.vhdr$", "", path, ignore.case = TRUE)
  data_file <- header$data_file
  if (is.null(data_file)) {
    data_file <- paste0(base_path, ".eeg")
  } else if (!file.exists(data_file)) {
    # Try relative path from header file directory
    data_file <- file.path(dirname(path), data_file)
  }

  if (!file.exists(data_file)) {
    stop("Data file not found: ", data_file, call. = FALSE)
  }

  # Determine marker file path
  marker_file <- header$marker_file
  if (is.null(marker_file)) {
    marker_file <- paste0(base_path, ".vmrk")
  } else if (!file.exists(marker_file)) {
    marker_file <- file.path(dirname(path), marker_file)
  }

  # Read binary data
  n_channels <- header$n_channels
  data_format <- header$data_format
  binary_format <- header$binary_format
  byte_order <- header$byte_order

  # Determine bytes per sample based on format
  bytes_per_sample <- switch(binary_format,
    "INT_16" = 2L,
    "INT_32" = 4L,
    "IEEE_FLOAT_32" = 4L,
    "IEEE_FLOAT_64" = 8L,
    2L  # default to INT_16
  )

  # Read raw data
  file_size <- file.info(data_file)$size
  n_samples <- file_size / (n_channels * bytes_per_sample)

  if (n_samples != floor(n_samples)) {
    warning("Data file size does not match expected dimensions", call. = FALSE)
    n_samples <- floor(n_samples)
  }

  # Determine data type for reading
  data_type <- switch(binary_format,
    "INT_16" = "integer",
    "INT_32" = "integer",
    "IEEE_FLOAT_32" = "double",
    "IEEE_FLOAT_64" = "double",
    "integer"
  )

  data_size <- switch(binary_format,
    "INT_16" = 2L,
    "INT_32" = 4L,
    "IEEE_FLOAT_32" = 4L,
    "IEEE_FLOAT_64" = 8L,
    2L
  )

  signed <- TRUE
  endian <- if (byte_order == "BIG_ENDIAN") "big" else "little"

  # Read data based on orientation
  con <- file(data_file, "rb")
  on.exit(close(con), add = TRUE)

  if (data_format == "BINARY" && header$data_orientation == "MULTIPLEXED") {
    # Multiplexed: samples are interleaved [ch1_s1, ch2_s1, ..., chN_s1, ch1_s2, ...]
    raw_data <- readBin(con, what = data_type, n = n_channels * n_samples,
                        size = data_size, signed = signed, endian = endian)
    signal_data <- matrix(raw_data, nrow = n_samples, ncol = n_channels, byrow = TRUE)
  } else if (data_format == "BINARY" && header$data_orientation == "VECTORIZED") {
    # Vectorized: all samples of one channel, then next channel
    raw_data <- readBin(con, what = data_type, n = n_channels * n_samples,
                        size = data_size, signed = signed, endian = endian)
    signal_data <- matrix(raw_data, nrow = n_samples, ncol = n_channels, byrow = FALSE)
  } else {
    stop("Unsupported data format: ", data_format, call. = FALSE)
  }

  # Apply scaling (resolution) to convert to microvolts
  for (i in seq_len(n_channels)) {
    resolution <- header$channel_info$resolution[i]
    if (!is.na(resolution) && resolution != 0) {
      signal_data[, i] <- signal_data[, i] * resolution
    }
  }

  # Select channels if specified
  ch_names <- header$channel_info$name
  if (!is.null(channels)) {
    ch_idx <- match(channels, ch_names)
    if (any(is.na(ch_idx))) {
      missing <- channels[is.na(ch_idx)]
      stop("Channels not found: ", paste(missing, collapse = ", "), call. = FALSE)
    }
    signal_data <- signal_data[, ch_idx, drop = FALSE]
    ch_names <- ch_names[ch_idx]
    header$channel_info <- header$channel_info[ch_idx, , drop = FALSE]
  }

  # Create channel metadata
  col_data <- S4Vectors::DataFrame(
    label = ch_names,
    unit = header$channel_info$unit,
    resolution = header$channel_info$resolution
  )

  # Create PhysioExperiment
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = signal_data),
    colData = col_data,
    samplingRate = header$sampling_rate
  )

  # Read and add events from marker file
  if (file.exists(marker_file)) {
    events <- .parseBrainVisionMarkers(marker_file, header$sampling_rate)
    if (!is.null(events) && nEvents(events) > 0) {
      pe <- setEvents(pe, events)
    }
  }

  .recordProv(pe, input_assay = NA_character_, output_assay = "raw",
              .package = "PhysioIO")
}

#' Write PhysioExperiment to BrainVision format
#'
#' Saves a PhysioExperiment object to BrainVision format (three files:
#' .vhdr header, .vmrk markers, .eeg binary data).
#'
#' @param x A PhysioExperiment object.
#' @param path Output path (without extension, or with .vhdr extension).
#' @param overwrite Logical. If TRUE, overwrites existing files.
#' @param binary_format Binary format for data: "IEEE_FLOAT_32" (default),
#'   "INT_16", or "INT_32".
#' @param assay_name Assay to export. If NULL, uses default assay.
#' @return Invisible NULL.
#' @export
#' @examples
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
#'   colData = S4Vectors::DataFrame(label = paste0("Ch", 1:10)),
#'   samplingRate = 100
#' )
#' base <- tempfile()
#' writeBrainVision(pe, base)
#' unlink(paste0(base, c(".vhdr", ".vmrk", ".eeg")))
writeBrainVision <- function(x, path, overwrite = FALSE,
                             binary_format = c("IEEE_FLOAT_32", "INT_16", "INT_32"),
                             assay_name = NULL) {
  stopifnot(inherits(x, "PhysioExperiment"))
  binary_format <- match.arg(binary_format)

  # Remove extension if present
  base_path <- sub("\\.(vhdr|vmrk|eeg)$", "", path, ignore.case = TRUE)

  vhdr_path <- paste0(base_path, ".vhdr")
  vmrk_path <- paste0(base_path, ".vmrk")
  eeg_path <- paste0(base_path, ".eeg")

  # Check for existing files
  if (!overwrite) {
    existing <- c(vhdr_path, vmrk_path, eeg_path)[file.exists(c(vhdr_path, vmrk_path, eeg_path))]
    if (length(existing) > 0) {
      stop("Files already exist: ", paste(basename(existing), collapse = ", "),
           ". Use overwrite = TRUE to replace.", call. = FALSE)
    }
  }

  # Get data
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

  n_samples <- dims[1]
  n_channels <- dims[2]

  # Get channel information
  ch_names <- channelNames(x)
  if (is.null(ch_names) || length(ch_names) != n_channels) {
    ch_names <- paste0("Ch", seq_len(n_channels))
  }

  sr <- samplingRate(x)
  if (is.na(sr) || sr <= 0) {
    warning("Invalid sampling rate. Setting to 1 Hz.", call. = FALSE)
    sr <- 1
  }

  # Write binary data file
  .writeBrainVisionData(data, eeg_path, binary_format)

  # Write header file
  .writeBrainVisionHeader(vhdr_path, basename(eeg_path), basename(vmrk_path),
                          n_channels, sr, ch_names, binary_format)

  # Write marker file
  events <- getEvents(x)
  .writeBrainVisionMarkers(vmrk_path, events, sr)

  invisible(NULL)
}

#' Internal: Parse BrainVision header file
#' @noRd
.parseBrainVisionHeader <- function(path) {
  lines <- readLines(path, warn = FALSE)
  lines <- trimws(lines)

  # Remove empty lines and comments
  lines <- lines[nchar(lines) > 0 & !grepl("^;", lines)]

  header <- list(
    data_file = NULL,
    marker_file = NULL,
    data_format = "BINARY",
    data_orientation = "MULTIPLEXED",
    binary_format = "INT_16",
    byte_order = "LITTLE_ENDIAN",
    n_channels = 0L,
    sampling_rate = NA_real_,
    channel_info = NULL
  )

  current_section <- ""

  for (line in lines) {
    # Section header
    if (grepl("^\\[.*\\]$", line)) {
      current_section <- gsub("\\[|\\]", "", line)
      next
    }

    # Key=Value pairs
    if (grepl("=", line)) {
      parts <- strsplit(line, "=", fixed = TRUE)[[1]]
      key <- trimws(parts[1])
      value <- if (length(parts) > 1) trimws(paste(parts[-1], collapse = "=")) else ""

      if (current_section == "Common Infos") {
        if (key == "DataFile") header$data_file <- value
        if (key == "MarkerFile") header$marker_file <- value
        if (key == "DataFormat") header$data_format <- toupper(value)
        if (key == "DataOrientation") header$data_orientation <- toupper(value)
        if (key == "NumberOfChannels") header$n_channels <- as.integer(value)
        if (key == "SamplingInterval") {
          # Sampling interval in microseconds
          interval_us <- as.numeric(value)
          header$sampling_rate <- 1e6 / interval_us
        }
      }

      if (current_section == "Binary Infos") {
        if (key == "BinaryFormat") header$binary_format <- toupper(value)
        if (key == "ByteOrder") header$byte_order <- toupper(value)
      }
    }
  }

  # Parse channel information
  header$channel_info <- .parseBrainVisionChannels(lines, header$n_channels)

  header
}

#' Internal: Parse BrainVision channel information
#' @noRd
.parseBrainVisionChannels <- function(lines, n_channels) {
  ch_info <- data.frame(
    name = character(n_channels),
    reference = character(n_channels),
    resolution = numeric(n_channels),
    unit = character(n_channels),
    stringsAsFactors = FALSE
  )

  in_channel_section <- FALSE

  for (line in lines) {
    if (grepl("^\\[Channel Infos\\]$", line, ignore.case = TRUE)) {
      in_channel_section <- TRUE
      next
    }
    if (grepl("^\\[", line) && in_channel_section) {
      break
    }

    if (in_channel_section && grepl("^Ch[0-9]+=", line)) {
      # Format: Ch1=name,reference,resolution,unit
      parts <- strsplit(line, "=", fixed = TRUE)[[1]]
      ch_num <- as.integer(gsub("Ch", "", parts[1]))
      if (ch_num > 0 && ch_num <= n_channels) {
        values <- strsplit(parts[2], ",", fixed = TRUE)[[1]]
        ch_info$name[ch_num] <- if (length(values) >= 1) trimws(values[1]) else paste0("Ch", ch_num)
        ch_info$reference[ch_num] <- if (length(values) >= 2) trimws(values[2]) else ""
        ch_info$resolution[ch_num] <- if (length(values) >= 3) as.numeric(values[3]) else 1
        ch_info$unit[ch_num] <- if (length(values) >= 4) trimws(values[4]) else "uV"
      }
    }
  }

  # Fill in missing channel names
  missing <- ch_info$name == ""
  if (any(missing)) {
    ch_info$name[missing] <- paste0("Ch", which(missing))
  }

  ch_info
}

#' Internal: Parse BrainVision marker file
#' @noRd
.parseBrainVisionMarkers <- function(path, sampling_rate) {
  if (!file.exists(path)) {
    return(NULL)
  }

  lines <- readLines(path, warn = FALSE)
  lines <- trimws(lines)

  onset <- numeric()
  duration <- numeric()
  type <- character()
  value <- character()

  in_marker_section <- FALSE

  for (line in lines) {
    if (grepl("^\\[Marker Infos\\]$", line, ignore.case = TRUE)) {
      in_marker_section <- TRUE
      next
    }
    if (grepl("^\\[", line) && in_marker_section) {
      break
    }

    if (in_marker_section && grepl("^Mk[0-9]+=", line)) {
      # Format: Mk1=type,description,position,size,channel
      parts <- strsplit(line, "=", fixed = TRUE)[[1]]
      if (length(parts) >= 2) {
        values <- strsplit(parts[2], ",", fixed = TRUE)[[1]]
        if (length(values) >= 3) {
          mk_type <- trimws(values[1])
          mk_desc <- if (length(values) >= 2) trimws(values[2]) else ""
          mk_pos <- as.numeric(values[3])
          mk_size <- if (length(values) >= 4) as.numeric(values[4]) else 1

          # Convert sample position to seconds
          onset <- c(onset, (mk_pos - 1) / sampling_rate)
          duration <- c(duration, mk_size / sampling_rate)
          type <- c(type, mk_type)
          value <- c(value, mk_desc)
        }
      }
    }
  }

  if (length(onset) == 0) {
    return(NULL)
  }

  PhysioEvents(
    onset = onset,
    duration = duration,
    type = type,
    value = value
  )
}

#' Internal: Write BrainVision data file
#' @noRd
.writeBrainVisionData <- function(data, path, binary_format) {
  con <- file(path, "wb")
  on.exit(close(con), add = TRUE)

  n_samples <- nrow(data)
  n_channels <- ncol(data)

  # Convert data to appropriate format and write multiplexed
  for (i in seq_len(n_samples)) {
    row_data <- data[i, ]

    if (binary_format == "IEEE_FLOAT_32") {
      writeBin(as.numeric(row_data), con, size = 4L, endian = "little")
    } else if (binary_format == "INT_16") {
      # Scale to int16 range
      int_data <- as.integer(round(row_data))
      int_data <- pmax(pmin(int_data, 32767L), -32768L)
      writeBin(int_data, con, size = 2L, endian = "little")
    } else if (binary_format == "INT_32") {
      int_data <- as.integer(round(row_data))
      writeBin(int_data, con, size = 4L, endian = "little")
    }
  }
}

#' Internal: Write BrainVision header file
#' @noRd
.writeBrainVisionHeader <- function(path, data_file, marker_file,
                                    n_channels, sampling_rate, ch_names,
                                    binary_format) {
  # Sampling interval in microseconds. Do NOT round to an integer: e.g. 256 Hz
  # is 3906.25 us, and truncating to 3906 reads back as 256.0164 Hz. BrainVision
  # permits a fractional SamplingInterval; format without scientific notation.
  sampling_interval <- format(1e6 / sampling_rate, scientific = FALSE,
                              trim = TRUE)

  lines <- c(
    "Brain Vision Data Exchange Header File Version 1.0",
    "; Data created by PhysioIO R package",
    "",
    "[Common Infos]",
    paste0("DataFile=", data_file),
    paste0("MarkerFile=", marker_file),
    "DataFormat=BINARY",
    "DataOrientation=MULTIPLEXED",
    paste0("NumberOfChannels=", n_channels),
    paste0("SamplingInterval=", sampling_interval),
    "",
    "[Binary Infos]",
    paste0("BinaryFormat=", binary_format),
    "",
    "[Channel Infos]",
    "; Each entry: Ch<number>=<name>,<reference>,<resolution>,<unit>"
  )

  # Add channel info
  for (i in seq_len(n_channels)) {
    resolution <- if (binary_format == "IEEE_FLOAT_32") 1 else 0.1
    # microvolts unit via \u00b5 escape so the R source stays ASCII (R CMD check
    # portability) while the written byte output ("\u00b5V") is unchanged.
    lines <- c(lines, sprintf("Ch%d=%s,,%.6f,\u00b5V", i, ch_names[i], resolution))
  }

  writeLines(lines, path)
}

#' Internal: Write BrainVision marker file
#' @noRd
.writeBrainVisionMarkers <- function(path, events, sampling_rate) {
  lines <- c(
    "Brain Vision Data Exchange Marker File Version 1.0",
    "; Data created by PhysioIO R package",
    "",
    "[Common Infos]",
    "DataFile=",
    "",
    "[Marker Infos]",
    "; Each entry: Mk<number>=<type>,<description>,<position>,<size>,<channel>",
    "; Fields are delimited by commas, some fields might be omitted",
    "; Position is 1-based sample number"
  )

  if (!is.null(events) && nEvents(events) > 0) {
    event_df <- events@events
    for (i in seq_len(nrow(event_df))) {
      # Convert seconds to 1-based sample position
      position <- round(event_df$onset[i] * sampling_rate) + 1
      size <- max(1, round(event_df$duration[i] * sampling_rate))
      mk_type <- event_df$type[i]
      mk_value <- if (!is.na(event_df$value[i])) event_df$value[i] else ""

      lines <- c(lines, sprintf("Mk%d=%s,%s,%d,%d,0", i, mk_type, mk_value, position, size))
    }
  }

  writeLines(lines, path)
}
