#' GDF (General Data Format) File I/O for PhysioExperiment
#'
#' Functions for reading and writing GDF format files. GDF is designed to
#' overcome limitations of EDF and is commonly used in BCI research.
#' Supports GDF version 1.x and 2.x.

#' Read PhysioExperiment from GDF file
#'
#' Reads physiological signal data from a GDF (General Data Format) file.
#' GDF is an extension of EDF with improved features including better
#' event support, more data types, and subject information.
#'
#' @param path Path to the GDF file.
#' @param channels Optional integer vector of channel indices or character
#'   vector of channel names to load. If NULL, loads all channels.
#' @param start_time Optional start time in seconds for selective loading.
#' @param end_time Optional end time in seconds for selective loading.
#' @return A PhysioExperiment object.
#' @export
#' @examples
#' # Round-trip a small recording through a temporary GDF file
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(300), nrow = 100, ncol = 3)),
#'   colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz")),
#'   samplingRate = 100
#' )
#' tmp <- tempfile(fileext = ".gdf")
#' writeGDF(pe, tmp)
#'
#' pe_in <- readGDF(tmp)
#' pe_sub <- readGDF(tmp, channels = c("Fz", "Cz"))
#' unlink(tmp)
readGDF <- function(path, channels = NULL, start_time = NULL, end_time = NULL) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  # Open file
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)

  # Read fixed header (256 bytes)
  header <- .readGDFFixedHeader(con)

  # Validate GDF signature
  if (!header$is_gdf) {
    stop("Not a valid GDF file", call. = FALSE)
  }

  n_signals <- header$n_signals

  # Read signal headers (256 bytes per signal)
  signal_headers <- .readGDFSignalHeaders(con, n_signals, header$version)

  # Calculate data dimensions
  n_records <- header$n_records
  samples_per_record <- signal_headers$samples_per_record

  # Check if all channels have same sampling rate (for simplicity)
  # If not, we'll need to resample
  max_samples <- max(samples_per_record)
  total_samples <- n_records * max_samples

  # Calculate time range
  max_sr <- max(signal_headers$sampling_rate)
  total_duration <- total_samples / max_sr

  # Handle time window selection
  start_sample <- 1L
  end_sample <- total_samples

  if (!is.null(start_time)) {
    start_sample <- max(1L, as.integer(start_time * max_sr) + 1L)
  }
  if (!is.null(end_time)) {
    end_sample <- min(total_samples, as.integer(end_time * max_sr))
  }

  n_samples_to_read <- end_sample - start_sample + 1L

  # Determine which records to read
  start_record <- ceiling(start_sample / max_samples)
  end_record <- ceiling(end_sample / max_samples)
  records_to_read <- end_record - start_record + 1

  # Calculate data types and sizes for each signal
  data_types <- .getGDFDataTypes(signal_headers$data_type)

  # Seek to the first record to be read. This must be UNCONDITIONAL: after
  # parsing the variable header the connection sits at 256 + 212*n_signals, but
  # each written signal header is padded to a full 256 bytes, so the data block
  # begins at 256 * (1 + n_signals). Skipping the seek for start_record == 1
  # (the default full read) started the data read inside the header padding.
  bytes_per_record <- sum(samples_per_record * data_types$size)
  seek(con, 256 * (1 + n_signals) + (start_record - 1) * bytes_per_record)

  # Allocate matrix for data
  signal_data <- matrix(NA_real_, nrow = records_to_read * max_samples, ncol = n_signals)

  # Read records
  for (rec in seq_len(records_to_read)) {
    for (sig in seq_len(n_signals)) {
      n_samp <- samples_per_record[sig]
      dtype <- data_types$type[sig]
      dsize <- data_types$size[sig]
      signed <- data_types$signed[sig]

      raw_values <- readBin(con, what = dtype, n = n_samp,
                           size = dsize, signed = signed, endian = "little")

      # Scale to physical values
      digital_min <- signal_headers$digital_min[sig]
      digital_max <- signal_headers$digital_max[sig]
      physical_min <- signal_headers$physical_min[sig]
      physical_max <- signal_headers$physical_max[sig]

      scale <- (physical_max - physical_min) / (digital_max - digital_min)
      offset <- physical_min - scale * digital_min

      values <- raw_values * scale + offset

      # Resample if needed (simple linear interpolation)
      if (n_samp < max_samples) {
        old_idx <- seq(1, max_samples, length.out = n_samp)
        new_idx <- seq_len(max_samples)
        values <- stats::approx(old_idx, values, new_idx)$y
      }

      row_start <- (rec - 1) * max_samples + 1
      row_end <- rec * max_samples
      signal_data[row_start:row_end, sig] <- values
    }
  }

  # Trim to requested time range
  # When no time window is specified, just trim to actual data length
  actual_rows <- nrow(signal_data)
  if (is.null(start_time) && is.null(end_time)) {
    # No time window - trim to total_samples or actual rows
    trim_end <- min(total_samples, actual_rows)
    signal_data <- signal_data[1:trim_end, , drop = FALSE]
  } else {
    # Time window specified
    local_start <- ((start_sample - 1) %% max_samples) + 1
    local_end <- min(local_start + n_samples_to_read - 1, actual_rows)
    signal_data <- signal_data[local_start:local_end, , drop = FALSE]
  }

  # Handle channel selection
  ch_names <- signal_headers$label
  ch_indices <- seq_len(n_signals)

  if (!is.null(channels)) {
    if (is.character(channels)) {
      ch_indices <- match(channels, ch_names)
      if (any(is.na(ch_indices))) {
        missing <- channels[is.na(ch_indices)]
        stop("Channels not found: ", paste(missing, collapse = ", "), call. = FALSE)
      }
    } else {
      ch_indices <- as.integer(channels)
      if (any(ch_indices < 1 | ch_indices > n_signals)) {
        stop("Channel indices out of range", call. = FALSE)
      }
    }
    signal_data <- signal_data[, ch_indices, drop = FALSE]
    ch_names <- ch_names[ch_indices]
    signal_headers <- lapply(signal_headers, function(x) x[ch_indices])
  }

  # Create channel metadata
  col_data <- S4Vectors::DataFrame(
    label = ch_names,
    transducer = signal_headers$transducer,
    unit = signal_headers$physical_dim,
    physical_min = signal_headers$physical_min,
    physical_max = signal_headers$physical_max
  )

  # Create PhysioExperiment
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = signal_data),
    colData = col_data,
    samplingRate = max_sr,
    metadata = list(
      gdf_version = header$version,
      patient_id = header$patient_id,
      recording_id = header$recording_id,
      start_datetime = header$start_datetime
    )
  )

  # Read events if present (GDF 2.x stores events in special way)
  events <- .readGDFEvents(path, header, max_sr)
  if (!is.null(events) && nEvents(events) > 0) {
    pe <- setEvents(pe, events)
  }

  pe
}

#' Write PhysioExperiment to GDF format
#'
#' Saves a PhysioExperiment object to GDF (General Data Format) version 2.x.
#'
#' @param x A PhysioExperiment object.
#' @param path Output file path.
#' @param patient_id Patient identifier string.
#' @param recording_id Recording identifier string.
#' @param overwrite Logical. If TRUE, overwrites existing file.
#' @param assay_name Assay to export. If NULL, uses default assay.
#' @return Invisible NULL.
#' @export
#' @examples
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
#'   colData = S4Vectors::DataFrame(label = paste0("Ch", 1:10)),
#'   samplingRate = 100
#' )
#' tmp <- tempfile(fileext = ".gdf")
#' writeGDF(pe, tmp)
#' unlink(tmp)
writeGDF <- function(x, path, patient_id = "", recording_id = "",
                     overwrite = FALSE, assay_name = NULL) {
  stopifnot(inherits(x, "PhysioExperiment"))

  if (file.exists(path) && !overwrite) {
    stop("File already exists: ", path, ". Use overwrite = TRUE to replace.",
         call. = FALSE)
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

  sr <- samplingRate(x)
  if (is.na(sr) || sr <= 0) {
    warning("Invalid sampling rate. Setting to 256 Hz.", call. = FALSE)
    sr <- 256
  }

  # Get channel names
  ch_names <- channelNames(x)
  if (is.null(ch_names) || length(ch_names) != n_channels) {
    ch_names <- paste0("Ch", seq_len(n_channels))
  }

  # Calculate record structure
  # Use 1 second records
  samples_per_record <- as.integer(sr)
  n_records <- ceiling(n_samples / samples_per_record)

  # Pad data if needed
  total_expected <- n_records * samples_per_record
  if (n_samples < total_expected) {
    pad_rows <- total_expected - n_samples
    data <- rbind(data, matrix(0, nrow = pad_rows, ncol = n_channels))
  }

  # Calculate physical/digital ranges
  data_range <- apply(data, 2, range, na.rm = TRUE)
  physical_min <- data_range[1, ]
  physical_max <- data_range[2, ]

  # Ensure non-zero range
  zero_range <- physical_max == physical_min
  physical_max[zero_range] <- physical_max[zero_range] + 1

  # Use int16 for storage
  digital_min <- rep(-32768L, n_channels)
  digital_max <- rep(32767L, n_channels)

  # Open file for writing
  con <- file(path, "wb")
  on.exit(close(con), add = TRUE)

  # Write fixed header
  .writeGDFFixedHeader(con, n_channels, n_records, samples_per_record,
                       patient_id, recording_id)

  # Write signal headers
  .writeGDFSignalHeaders(con, n_channels, ch_names, samples_per_record,
                         physical_min, physical_max, digital_min, digital_max)

  # Write data records
  for (rec in seq_len(n_records)) {
    row_start <- (rec - 1) * samples_per_record + 1
    row_end <- min(rec * samples_per_record, nrow(data))

    for (ch in seq_len(n_channels)) {
      values <- data[row_start:row_end, ch]

      # Scale to digital values
      scale <- (digital_max[ch] - digital_min[ch]) / (physical_max[ch] - physical_min[ch])
      offset <- digital_min[ch] - scale * physical_min[ch]
      int_values <- as.integer(round(values * scale + offset))
      int_values <- pmax(pmin(int_values, 32767L), -32768L)

      # Pad if needed
      if (length(int_values) < samples_per_record) {
        int_values <- c(int_values, rep(0L, samples_per_record - length(int_values)))
      }

      writeBin(int_values, con, size = 2L, endian = "little")
    }
  }

  # Write events if present
  events <- getEvents(x)
  if (!is.null(events) && nEvents(events) > 0) {
    .writeGDFEvents(con, events, sr)
  }

  invisible(NULL)
}

#' Internal: Read GDF fixed header
#' @noRd
.readGDFFixedHeader <- function(con) {
  header <- list()

  # Version ID (8 bytes)
  version_str <- rawToChar(readBin(con, "raw", 8))
  header$is_gdf <- grepl("^GDF", version_str)
  # Reject non-GDF input up front: the version-dependent reads below compare
  # against header$version, which would be NA (erroring with an opaque
  # "missing value" message) for a non-GDF file.
  if (!header$is_gdf) {
    stop("Not a valid GDF file", call. = FALSE)
  }
  header$version <- as.numeric(sub("GDF ", "", trimws(version_str)))

  # Patient ID (80 bytes) - varies by version
  if (header$version >= 2.0) {
    header$patient_id <- trimws(rawToChar(readBin(con, "raw", 66)))
    # Additional fields in GDF 2.x
    readBin(con, "raw", 14)  # Skip remaining patient fields
  } else {
    header$patient_id <- trimws(rawToChar(readBin(con, "raw", 80)))
  }

  # Recording ID (80 bytes)
  if (header$version >= 2.0) {
    header$recording_id <- trimws(rawToChar(readBin(con, "raw", 64)))
    readBin(con, "raw", 16)  # Skip additional recording fields
  } else {
    header$recording_id <- trimws(rawToChar(readBin(con, "raw", 80)))
  }

  # Start date/time
  if (header$version >= 2.0) {
    # GDF 2.x: 8 bytes as uint64 (100ns since 0000-01-01)
    datetime_raw <- readBin(con, "double", 1, size = 8)
    header$start_datetime <- as.POSIXct("2000-01-01", tz = "UTC")  # Placeholder
  } else {
    # GDF 1.x: ASCII format
    date_str <- trimws(rawToChar(readBin(con, "raw", 8)))
    header$start_datetime <- tryCatch(
      as.POSIXct(date_str, format = "%d.%m.%y", tz = "UTC"),
      error = function(e) NA
    )
  }

  # Header length (8 bytes in GDF 2.x, varies in 1.x)
  if (header$version >= 2.0) {
    header$header_bytes <- readBin(con, "integer", 1, size = 2, signed = FALSE)
    readBin(con, "raw", 6)  # Equipment ID and other fields
  } else {
    readBin(con, "raw", 44)  # Skip to record count
  }

  # Number of data records (8 bytes) - use raw bytes and convert
  n_rec_raw <- readBin(con, "raw", 8)
  header$n_records <- as.integer(sum(as.numeric(n_rec_raw) * (256^(0:7))))
  if (is.na(header$n_records) || header$n_records < 0) {
    header$n_records <- 0L
  }

  # Record duration (8 bytes as double or fraction)
  if (header$version >= 2.0) {
    numerator <- readBin(con, "integer", 1, size = 4)
    denominator <- readBin(con, "integer", 1, size = 4)
    header$record_duration <- if (denominator > 0) numerator / denominator else 1
  } else {
    header$record_duration <- readBin(con, "double", 1, size = 8)
  }

  # Number of signals (4 bytes in GDF 2.x)
  header$n_signals <- readBin(con, "integer", 1, size = if (header$version >= 2.0) 2L else 4L,
                              signed = FALSE)

  # Skip to end of fixed header (256 bytes total)
  current_pos <- seek(con)
  if (current_pos < 256) {
    readBin(con, "raw", 256 - current_pos)
  }

  header
}

#' Internal: Read GDF signal headers
#' @noRd
.readGDFSignalHeaders <- function(con, n_signals, version) {
  headers <- list(
    label = character(n_signals),
    transducer = character(n_signals),
    physical_dim = character(n_signals),
    physical_min = numeric(n_signals),
    physical_max = numeric(n_signals),
    digital_min = numeric(n_signals),
    digital_max = numeric(n_signals),
    prefiltering = character(n_signals),
    samples_per_record = integer(n_signals),
    data_type = integer(n_signals),
    sampling_rate = numeric(n_signals)
  )

  # Read each field for all signals
  # Label (16 bytes per signal)
  for (i in seq_len(n_signals)) {
    headers$label[i] <- trimws(rawToChar(readBin(con, "raw", 16)))
  }

  # Transducer type (80 bytes per signal)
  for (i in seq_len(n_signals)) {
    headers$transducer[i] <- trimws(rawToChar(readBin(con, "raw", 80)))
  }

  # Physical dimension (8 bytes per signal in GDF 2.x, 6 in 1.x)
  dim_bytes <- if (version >= 2.0) 6L else 8L
  for (i in seq_len(n_signals)) {
    headers$physical_dim[i] <- trimws(rawToChar(readBin(con, "raw", dim_bytes)))
    if (version >= 2.0) readBin(con, "raw", 2)  # Physical dimension code
  }

  # Physical minimum (8 bytes per signal)
  for (i in seq_len(n_signals)) {
    headers$physical_min[i] <- readBin(con, "double", 1, size = 8)
  }

  # Physical maximum (8 bytes per signal)
  for (i in seq_len(n_signals)) {
    headers$physical_max[i] <- readBin(con, "double", 1, size = 8)
  }

  # Digital minimum (8 bytes per signal in GDF 2.x)
  if (version >= 2.0) {
    for (i in seq_len(n_signals)) {
      headers$digital_min[i] <- readBin(con, "double", 1, size = 8)
    }
  } else {
    for (i in seq_len(n_signals)) {
      headers$digital_min[i] <- readBin(con, "integer", 1, size = 4)
    }
  }

  # Digital maximum
  if (version >= 2.0) {
    for (i in seq_len(n_signals)) {
      headers$digital_max[i] <- readBin(con, "double", 1, size = 8)
    }
  } else {
    for (i in seq_len(n_signals)) {
      headers$digital_max[i] <- readBin(con, "integer", 1, size = 4)
    }
  }

  # Skip prefiltering or other fields
  if (version >= 2.0) {
    # GDF 2.x has different structure
    readBin(con, "raw", 68 * n_signals)  # Skip to samples per record
  } else {
    for (i in seq_len(n_signals)) {
      headers$prefiltering[i] <- trimws(rawToChar(readBin(con, "raw", 80)))
    }
  }

  # Samples per record (4 bytes per signal)
  for (i in seq_len(n_signals)) {
    headers$samples_per_record[i] <- readBin(con, "integer", 1, size = 4)
  }

  # Data type (4 bytes per signal in GDF 2.x)
  if (version >= 2.0) {
    for (i in seq_len(n_signals)) {
      headers$data_type[i] <- readBin(con, "integer", 1, size = 4)
    }
  } else {
    headers$data_type <- rep(3L, n_signals)  # Default to int16
  }

  # Calculate sampling rates
  # Assuming record duration of 1 second if not specified
  headers$sampling_rate <- headers$samples_per_record

  headers
}

#' Internal: Get GDF data types
#' @noRd
.getGDFDataTypes <- function(type_codes) {
  n <- length(type_codes)
  result <- list(
    type = character(n),
    size = integer(n),
    signed = logical(n)
  )

  for (i in seq_len(n)) {
    code <- type_codes[i]
    # GDF type codes
    switch(as.character(code),
      "1" = { result$type[i] <- "integer"; result$size[i] <- 1L; result$signed[i] <- TRUE },   # int8
      "2" = { result$type[i] <- "integer"; result$size[i] <- 1L; result$signed[i] <- FALSE },  # uint8
      "3" = { result$type[i] <- "integer"; result$size[i] <- 2L; result$signed[i] <- TRUE },   # int16
      "4" = { result$type[i] <- "integer"; result$size[i] <- 2L; result$signed[i] <- FALSE },  # uint16
      "5" = { result$type[i] <- "integer"; result$size[i] <- 4L; result$signed[i] <- TRUE },   # int32
      "6" = { result$type[i] <- "integer"; result$size[i] <- 4L; result$signed[i] <- FALSE },  # uint32
      "7" = { result$type[i] <- "integer"; result$size[i] <- 8L; result$signed[i] <- TRUE },   # int64
      "16" = { result$type[i] <- "double"; result$size[i] <- 4L; result$signed[i] <- TRUE },   # float32
      "17" = { result$type[i] <- "double"; result$size[i] <- 8L; result$signed[i] <- TRUE },   # float64
      { result$type[i] <- "integer"; result$size[i] <- 2L; result$signed[i] <- TRUE }  # default int16
    )
  }

  result
}

#' Internal: Read GDF events
#' @noRd
.readGDFEvents <- function(path, header, sampling_rate) {
  # GDF events are stored after data records
  # This is a simplified implementation
  # Full implementation would parse event table format

  # For now, return NULL - events parsing requires more complex handling
  NULL
}

#' Internal: Write GDF fixed header
#' @noRd
.writeGDFFixedHeader <- function(con, n_channels, n_records, samples_per_record,
                                  patient_id, recording_id) {
  # Version ID (8 bytes) - GDF 2.20
  version_str <- sprintf("%-8s", "GDF 2.20")
  writeBin(charToRaw(version_str), con)

  # Patient ID (66 bytes + 14 bytes reserved)
  patient_str <- sprintf("%-66s", substr(patient_id, 1, 66))
  writeBin(charToRaw(patient_str), con)
  writeBin(raw(14), con)

  # Recording ID (64 bytes + 16 bytes reserved)
  recording_str <- sprintf("%-64s", substr(recording_id, 1, 64))
  writeBin(charToRaw(recording_str), con)
  writeBin(raw(16), con)

  # Start datetime (8 bytes) - use current time
  writeBin(raw(8), con)

  # Header length (2 bytes)
  header_bytes <- 256L * (1L + n_channels)
  writeBin(as.integer(header_bytes), con, size = 2)

  # Equipment ID and reserved (6 bytes)
  writeBin(raw(6), con)

  # Number of data records (8 bytes as little-endian)
  n_rec_bytes <- raw(8)
  n_rec <- as.integer(n_records)
  for (i in 1:8) {
    n_rec_bytes[i] <- as.raw(n_rec %% 256)
    n_rec <- n_rec %/% 256
  }
  writeBin(n_rec_bytes, con)

  # Record duration (numerator 4 bytes, denominator 4 bytes)
  writeBin(as.integer(1L), con, size = 4)  # 1 second numerator
  writeBin(as.integer(1L), con, size = 4)  # denominator

  # Number of signals (2 bytes)
  writeBin(as.integer(n_channels), con, size = 2)

  # Pad to 256 bytes (8+80+80+8+8+8+8+2 = 202, need 54 more)
  writeBin(raw(54), con)
}

#' Internal: Write GDF signal headers
#' @noRd
.writeGDFSignalHeaders <- function(con, n_channels, ch_names, samples_per_record,
                                    physical_min, physical_max, digital_min, digital_max) {
  # Labels (16 bytes each)
  for (i in seq_len(n_channels)) {
    label <- sprintf("%-16s", substr(ch_names[i], 1, 16))
    writeBin(charToRaw(label), con)
  }

  # Transducer (80 bytes each)
  for (i in seq_len(n_channels)) {
    writeBin(charToRaw(sprintf("%-80s", "")), con)
  }

  # Physical dimension (6 bytes + 2 bytes code)
  for (i in seq_len(n_channels)) {
    writeBin(charToRaw(sprintf("%-6s", "uV")), con)
    writeBin(as.integer(4275L), con, size = 2)  # uV code
  }

  # Physical min/max (8 bytes each)
  for (i in seq_len(n_channels)) {
    writeBin(as.double(physical_min[i]), con, size = 8)
  }
  for (i in seq_len(n_channels)) {
    writeBin(as.double(physical_max[i]), con, size = 8)
  }

  # Digital min/max (8 bytes each for GDF 2.x)
  for (i in seq_len(n_channels)) {
    writeBin(as.double(digital_min[i]), con, size = 8)
  }
  for (i in seq_len(n_channels)) {
    writeBin(as.double(digital_max[i]), con, size = 8)
  }

  # Reserved/other fields (68 bytes each)
  for (i in seq_len(n_channels)) {
    writeBin(raw(68), con)
  }

  # Samples per record (4 bytes each)
  for (i in seq_len(n_channels)) {
    writeBin(as.integer(samples_per_record), con, size = 4)
  }

  # Data type (4 bytes each) - int16 = 3
  for (i in seq_len(n_channels)) {
    writeBin(as.integer(3L), con, size = 4)
  }

  # Pad remaining bytes to complete 256 bytes per signal
  bytes_written <- 16 + 80 + 8 + 8 + 8 + 8 + 8 + 68 + 4 + 4
  remaining <- 256 - bytes_written
  if (remaining > 0) {
    for (i in seq_len(n_channels)) {
      writeBin(raw(remaining), con)
    }
  }
}

#' Internal: Write GDF events
#' @noRd
.writeGDFEvents <- function(con, events, sampling_rate) {
  # GDF event table format
  # Mode 1: [typ(2), pos(4)] for each event
  # Mode 3: [typ(2), pos(4), dur(4), chn(2)] for each event

  if (is.null(events) || nEvents(events) == 0) {
    return()
  }

  event_df <- events@events
  n_events <- nrow(event_df)

  # Write event table header
  # Mode (1 byte) + reserved (3 bytes) + number of events (4 bytes)
  writeBin(as.raw(3L), con)  # Mode 3
  writeBin(raw(3), con)
  writeBin(as.integer(n_events), con, size = 4)

  # Write each event
  for (i in seq_len(n_events)) {
    # Type (2 bytes) - use hash of type string
    type_code <- as.integer(abs(digest::digest2int(event_df$type[i])) %% 65535)
    writeBin(as.integer(type_code), con, size = 2)

    # Position (4 bytes) - sample number
    pos <- as.integer(round(event_df$onset[i] * sampling_rate))
    writeBin(pos, con, size = 4)

    # Duration (4 bytes)
    dur <- as.integer(round(event_df$duration[i] * sampling_rate))
    writeBin(dur, con, size = 4)

    # Channel (2 bytes) - 0 for all channels
    writeBin(as.integer(0L), con, size = 2)
  }
}
