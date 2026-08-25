#' EDF/EDF+ file I/O
#'
#' Functions for reading European Data Format (EDF/EDF+) files commonly used
#' for EEG, PSG, and other physiological recordings.

#' Read EDF/EDF+ file
#'
#' Reads an EDF or EDF+ file and returns a PhysioExperiment object.
#'
#' @param path Path to the EDF file.
#' @param channels Optional character vector of channel names to load.
#'   If NULL, all channels are loaded.
#' @param start_time Optional start time in seconds for reading a subset.
#' @param end_time Optional end time in seconds for reading a subset.
#' @param resample Logical. If \code{FALSE} (default) and channels have
#'   differing native sampling rates, the native rates are preserved by
#'   returning a \code{MultiRatePhysioExperiment} (one stream per rate). If
#'   \code{TRUE}, all channels are resampled to the highest rate and a single
#'   \code{PhysioExperiment} is returned (legacy behaviour).
#' @return A \code{\link[PhysioCore:PhysioExperiment-class]{PhysioExperiment}}
#'   with the EDF signal data in the \code{"raw"} assay, or - when channels have
#'   differing native rates and \code{resample = FALSE} - a
#'   \code{\link[PhysioCore]{MultiRatePhysioExperiment}}. Channel metadata
#'   (label, transducer, physical dimensions, digital/physical min/max) are
#'   stored in \code{colData}, and recording metadata in \code{metadata}.
#' @details
#' EDF (European Data Format) is a standard file format for storing
#' multichannel physiological signals. EDF+ extends this with annotations
#' and discontinuous recordings.
#'
#' The function parses the EDF header to extract:
#' - Channel labels and types
#' - Sampling rates (may differ per channel)
#' - Physical dimensions (units)
#' - Recording start date/time
#'
#' If channels have different native sampling rates, the rates are preserved by
#' returning a \code{MultiRatePhysioExperiment} (one stream per rate); pass
#' \code{resample = TRUE} for the legacy single-rate behaviour.
#' @references
#'   Kemp, B., et al. (1992). "A simple format for exchange of digitized
#'   polygraphic recordings." Electroencephalography and Clinical
#'   Neurophysiology, 82(5), 391-393. doi:10.1016/0013-4694(92)90009-7
#' @seealso \code{\link{writeEDF}}, \code{\link{readBIDS}},
#'   \code{\link{readPhysioHDF5}}, \code{\link{readCSV}}
#' @export
#' @examples
#' # Round-trip a small recording through a temporary EDF file
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
#'   colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "C3", "C4")),
#'   samplingRate = 100
#' )
#' tmp <- tempfile(fileext = ".edf")
#' writeEDF(pe, tmp)
#'
#' # Read the whole file back
#' pe_in <- readEDF(tmp)
#' dim(SummarizedExperiment::assay(pe_in, "raw"))
#'
#' # Read only specific channels
#' pe_sub <- readEDF(tmp, channels = c("Fp1", "C3"))
#'
#' unlink(tmp)
readEDF <- function(path, channels = NULL, start_time = NULL, end_time = NULL,
                    resample = FALSE) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  # Open file in binary mode
  con <- file(path, "rb")
  on.exit(close(con))

  # Read header (fixed 256 bytes)
  header <- .parseEDFHeader(con)

  # Read signal headers
  ns <- header$num_signals
  signal_headers <- .parseEDFSignalHeaders(con, ns)

  # Determine which channels to read
  if (!is.null(channels)) {
    channel_idx <- match(channels, signal_headers$label)
    if (any(is.na(channel_idx))) {
      missing <- channels[is.na(channel_idx)]
      stop("Channels not found: ", paste(missing, collapse = ", "), call. = FALSE)
    }
  } else {
    # Exclude EDF Annotations channel
    channel_idx <- which(signal_headers$label != "EDF Annotations")
    if (length(channel_idx) == 0) channel_idx <- seq_len(ns)
  }

  # Calculate data parameters
  n_records <- header$num_data_records
  record_duration <- header$data_record_duration
  total_duration <- n_records * record_duration

  # Calculate which records to read based on start_time/end_time
  start_record <- 1L
  end_record <- n_records

  if (!is.null(start_time)) {
    if (start_time < 0) start_time <- 0
    if (start_time >= total_duration) {
      stop("start_time exceeds recording duration", call. = FALSE)
    }
    start_record <- max(1L, as.integer(floor(start_time / record_duration)) + 1L)
  }

  if (!is.null(end_time)) {
    if (end_time > total_duration) end_time <- total_duration
    if (end_time <= 0 || (!is.null(start_time) && end_time <= start_time)) {
      stop("Invalid end_time", call. = FALSE)
    }
    end_record <- min(n_records, as.integer(ceiling(end_time / record_duration)))
  }

  records_to_read <- end_record - start_record + 1L

  # Read data records (with optional record range)
  data_list <- .readEDFData(con, signal_headers, n_records, channel_idx,
                            start_record = start_record, end_record = end_record)

  # Trim data to exact start_time/end_time within records
  if (!is.null(start_time) || !is.null(end_time)) {
    sample_rates <- signal_headers$samples_per_record[channel_idx] / record_duration
    common_sr <- max(sample_rates)

    # Calculate sample offsets within the loaded data
    loaded_start_time <- (start_record - 1) * record_duration
    start_offset <- if (!is.null(start_time)) {
      as.integer(round((start_time - loaded_start_time) * common_sr))
    } else {
      0L
    }

    loaded_end_time <- end_record * record_duration
    if (!is.null(end_time)) {
      effective_start <- if (!is.null(start_time)) start_time else 0
      samples_to_keep <- as.integer(round((end_time - max(effective_start, loaded_start_time)) * common_sr))
    } else {
      samples_to_keep <- NULL
    }

    # Trim each channel
    data_list <- lapply(data_list, function(ch_data) {
      n <- length(ch_data)
      start_idx <- min(start_offset + 1L, n)
      end_idx <- if (!is.null(samples_to_keep)) {
        min(start_offset + samples_to_keep, n)
      } else {
        n
      }
      ch_data[start_idx:end_idx]
    })
  }

  # Get annotations if EDF+
  annotations <- NULL
  annot_idx <- which(signal_headers$label == "EDF Annotations")
  if (length(annot_idx) > 0) {
    annotations <- .parseEDFAnnotations(con, signal_headers, n_records, annot_idx[1])
  }

  close(con)
  on.exit(NULL)

  # Build the container. Channels keep their native rates: differing rates
  # yield a MultiRatePhysioExperiment unless resample = TRUE.
  selected_headers <- lapply(signal_headers, function(x) x[channel_idx])
  sample_rates <- selected_headers$samples_per_record / record_duration

  meta <- list(
    patient_id = header$patient_id,
    recording_id = header$recording_id,
    start_date = header$start_date,
    start_time = header$start_time,
    file_type = if (header$version == "0       ") "EDF" else "EDF+",
    original_file = path
  )

  result <- .assembleEDFStreams(data_list, sample_rates, selected_headers, meta,
                                resample = resample)

  # Add annotations as events (on the reference stream when multi-rate)
  if (!is.null(annotations) && nrow(annotations) > 0) {
    ev <- PhysioEvents(
      onset = annotations$onset,
      duration = annotations$duration,
      type = rep("annotation", nrow(annotations)),
      value = annotations$annotation
    )
    if (methods::is(result, "MultiRatePhysioExperiment")) {
      s <- streams(result)
      s[[1]] <- setEvents(s[[1]], ev)
      streams(result) <- s
    } else {
      result <- setEvents(result, ev)
    }
  }

  .recordProv(result, input_assay = NA_character_, output_assay = "raw",
              .package = "PhysioIO")
}

#' Parse EDF main header
#' @noRd
.parseEDFHeader <- function(con) {
  version <- rawToChar(readBin(con, "raw", 8))
  patient_id <- trimws(rawToChar(readBin(con, "raw", 80)))
  recording_id <- trimws(rawToChar(readBin(con, "raw", 80)))
  start_date <- rawToChar(readBin(con, "raw", 8))
  start_time <- rawToChar(readBin(con, "raw", 8))
  header_bytes <- as.integer(trimws(rawToChar(readBin(con, "raw", 8))))
  reserved <- rawToChar(readBin(con, "raw", 44))
  num_data_records <- as.integer(trimws(rawToChar(readBin(con, "raw", 8))))
  data_record_duration <- as.numeric(trimws(rawToChar(readBin(con, "raw", 8))))
  num_signals <- as.integer(trimws(rawToChar(readBin(con, "raw", 4))))

  list(
    version = version,
    patient_id = patient_id,
    recording_id = recording_id,
    start_date = start_date,
    start_time = start_time,
    header_bytes = header_bytes,
    reserved = reserved,
    num_data_records = num_data_records,
    data_record_duration = data_record_duration,
    num_signals = num_signals
  )
}

#' Parse EDF signal headers
#' @noRd
.parseEDFSignalHeaders <- function(con, ns) {
  read_field <- function(n) {
    sapply(seq_len(ns), function(i) trimws(rawToChar(readBin(con, "raw", n))))
  }

  list(
    label = read_field(16),
    transducer = read_field(80),
    physical_dim = read_field(8),
    physical_min = as.numeric(read_field(8)),
    physical_max = as.numeric(read_field(8)),
    digital_min = as.integer(read_field(8)),
    digital_max = as.integer(read_field(8)),
    prefiltering = read_field(80),
    samples_per_record = as.integer(read_field(8)),
    reserved = read_field(32)
  )
}

#' Read EDF data records
#' @noRd
.readEDFData <- function(con, signal_headers, n_records, channel_idx,
                         start_record = 1L, end_record = NULL) {
  ns <- length(signal_headers$label)
  samples_per_record <- signal_headers$samples_per_record

  if (is.null(end_record)) end_record <- n_records
  records_to_read <- end_record - start_record + 1L

  # Initialize data lists for the records we're reading
  data_list <- lapply(channel_idx, function(i) {
    numeric(records_to_read * samples_per_record[i])
  })

  # Calculate scaling factors
  scale <- (signal_headers$physical_max - signal_headers$physical_min) /
           (signal_headers$digital_max - signal_headers$digital_min)
  offset <- signal_headers$physical_min - scale * signal_headers$digital_min

  # Skip records before start_record
  if (start_record > 1) {
    bytes_per_record <- sum(samples_per_record * 2)
    skip_bytes <- (start_record - 1) * bytes_per_record
    seek(con, seek(con) + skip_bytes)
  }

  # Read data records
  for (rec in seq_len(records_to_read)) {
    for (sig in seq_len(ns)) {
      n_samples <- samples_per_record[sig]
      raw_data <- readBin(con, "integer", n_samples, size = 2, signed = TRUE)

      if (sig %in% channel_idx) {
        idx <- which(channel_idx == sig)
        start <- (rec - 1) * n_samples + 1
        end <- rec * n_samples
        # Convert to physical values
        data_list[[idx]][start:end] <- raw_data * scale[sig] + offset[sig]
      }
    }
  }

  data_list
}

#' Parse EDF+ annotations
#' @noRd
.parseEDFAnnotations <- function(con, signal_headers, n_records, annot_idx) {
  # Seek to start of data
  seek(con, 256 + length(signal_headers$label) * 256)

  annotations <- data.frame(
    onset = numeric(0),
    duration = numeric(0),
    annotation = character(0),
    stringsAsFactors = FALSE
  )

  for (rec in seq_len(n_records)) {
    # Skip to annotation channel
    for (sig in seq_len(annot_idx - 1)) {
      skip_bytes <- signal_headers$samples_per_record[sig] * 2
      seek(con, seek(con) + skip_bytes)
    }

    # Read annotation data
    n_bytes <- signal_headers$samples_per_record[annot_idx] * 2
    raw_annot <- readBin(con, "raw", n_bytes)
    annot_str <- rawToChar(raw_annot[raw_annot != 0])

    # Parse TAL (Time-stamped Annotation List)
    parsed <- .parseTAL(annot_str)
    if (nrow(parsed) > 0) {
      annotations <- rbind(annotations, parsed)
    }

    # Skip remaining channels (guard against annot_idx being last)
    if (annot_idx < length(signal_headers$label)) {
      for (sig in (annot_idx + 1):length(signal_headers$label)) {
        skip_bytes <- signal_headers$samples_per_record[sig] * 2
        seek(con, seek(con) + skip_bytes)
      }
    }
  }

  annotations
}

#' Parse TAL (Time-stamped Annotation List)
#' @noRd
.parseTAL <- function(tal_string) {
  annotations <- data.frame(
    onset = numeric(0),
    duration = numeric(0),
    annotation = character(0),
    stringsAsFactors = FALSE
  )

  # Split by record separator (0x14 0x14 0x00)
  parts <- strsplit(tal_string, "\024\024")[[1]]

  for (part in parts) {
    if (nchar(part) == 0) next

    # Parse onset and duration
    match <- regexpr("^([+-]?[0-9.]+)(\025([0-9.]+))?\024(.*)$", part, perl = TRUE)
    if (match == -1) next

    onset <- as.numeric(sub("^([+-]?[0-9.]+).*", "\\1", part))
    duration_match <- regmatches(part, regexec("\025([0-9.]+)", part))
    duration <- if (length(duration_match[[1]]) > 1) as.numeric(duration_match[[1]][2]) else 0
    annot <- sub("^[+-]?[0-9.]+(\025[0-9.]+)?\024", "", part)

    if (!is.na(onset)) {
      annotations <- rbind(annotations, data.frame(
        onset = onset,
        duration = duration,
        annotation = annot,
        stringsAsFactors = FALSE
      ))
    }
  }

  annotations
}

#' Simple resampling helper
#' @noRd
.resampleSignal <- function(x, from_rate, to_rate) {
  if (from_rate == to_rate) return(x)

  n_old <- length(x)
  n_new <- round(n_old * to_rate / from_rate)
  t_old <- seq(0, 1, length.out = n_old)
  t_new <- seq(0, 1, length.out = n_new)

  stats::approx(t_old, x, t_new)$y
}

#' Assemble EDF/BDF channels into a PhysioExperiment or MultiRatePhysioExperiment
#'
#' When channels have differing native sampling rates and \code{resample} is
#' \code{FALSE} (the default), the native rates are preserved by returning a
#' \code{MultiRatePhysioExperiment} with one stream per distinct rate. When all
#' rates match, or \code{resample = TRUE}, a single \code{PhysioExperiment} is
#' returned (legacy behaviour: everything resampled to the highest rate).
#' @noRd
.assembleEDFStreams <- function(data_list, sample_rates, selected_headers, meta,
                                resample = FALSE) {
  common_sr <- max(sample_rates)
  multi <- length(unique(sample_rates)) > 1

  build_pe <- function(idx, sr) {
    n_samples <- length(data_list[[idx[1]]])
    m <- matrix(NA_real_, n_samples, length(idx))
    for (k in seq_along(idx)) m[, k] <- data_list[[idx[k]]]
    cd <- S4Vectors::DataFrame(
      label = selected_headers$label[idx],
      transducer = selected_headers$transducer[idx],
      physical_dim = selected_headers$physical_dim[idx],
      physical_min = selected_headers$physical_min[idx],
      physical_max = selected_headers$physical_max[idx],
      digital_min = selected_headers$digital_min[idx],
      digital_max = selected_headers$digital_max[idx]
    )
    PhysioExperiment(
      assays = S4Vectors::SimpleList(raw = m),
      rowData = S4Vectors::DataFrame(time_idx = seq_len(n_samples)),
      colData = cd, metadata = meta, samplingRate = sr
    )
  }

  if (multi && !resample) {
    # preserve native rates: one stream per distinct rate (fastest first)
    rates <- sort(unique(sample_rates), decreasing = TRUE)
    strs <- lapply(rates, function(r) build_pe(which(sample_rates == r), r))
    names(strs) <- paste0("rate_", sub("\\.", "p", format(rates, trim = TRUE)))
    return(PhysioCore::MultiRatePhysioExperiment(streams = strs,
                                                 reference_rate = common_sr))
  }

  if (multi) {
    # legacy: resample every channel to the common (highest) rate
    message("Resampling channels to common rate: ", common_sr, " Hz")
    data_list <- lapply(seq_along(data_list), function(i) {
      if (sample_rates[i] != common_sr) {
        .resampleSignal(data_list[[i]], sample_rates[i], common_sr)
      } else data_list[[i]]
    })
  }
  build_pe(seq_along(data_list), common_sr)
}

#' Write EDF file
#'
#' Writes a PhysioExperiment object to EDF format.
#'
#' @param x A PhysioExperiment object.
#' @param path Output file path.
#' @param patient_id Patient identification string.
#' @param recording_id Recording identification string.
#' @return Invisible \code{NULL}. The EDF file is written to \code{path} as a
#'   side effect.
#' @references
#'   Kemp, B., et al. (1992). "A simple format for exchange of digitized
#'   polygraphic recordings." Electroencephalography and Clinical
#'   Neurophysiology, 82(5), 391-393. doi:10.1016/0013-4694(92)90009-7
#' @seealso \code{\link{readEDF}}, \code{\link{writeBIDS}},
#'   \code{\link{writePhysioHDF5}}, \code{\link{writeCSV}}
#' @export
#' @examples
#' # Create a PhysioExperiment with EEG-like data
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
#'   colData = S4Vectors::DataFrame(label = paste0("Ch", 1:10)),
#'   samplingRate = 100
#' )
#'
#' # Export to EDF format in a temporary file
#' tmp <- tempfile(fileext = ".edf")
#' writeEDF(pe, tmp, patient_id = "Subject01", recording_id = "Session1")
#'
#' unlink(tmp)
writeEDF <- function(x, path, patient_id = "X", recording_id = "X")
{
  stopifnot(inherits(x, "PhysioExperiment"))

  sr <- samplingRate(x)
  if (is.na(sr) || sr <= 0) {
    stop("Valid sampling rate required for EDF export", call. = FALSE)
  }

  assay_name <- defaultAssay(x)
  data <- SummarizedExperiment::assay(x, assay_name)
  dims <- dim(data)

  # Handle 3D arrays with single sample (time x channel x 1) by dropping to 2D
  if (length(dims) == 3 && dims[3] == 1) {
    data <- data[, , 1, drop = TRUE]
    dims <- dim(data)
  }

  if (length(dims) != 2) {
    stop("Only 2D data (time x channel) or 3D with single sample can be exported to EDF", call. = FALSE)
  }

  n_samples <- dims[1]
  n_channels <- dims[2]

  # Get channel labels from colData (channels are in columns)
  col_data <- SummarizedExperiment::colData(x)
  if ("label" %in% names(col_data)) {
    labels <- as.character(col_data$label)
  } else {
    labels <- paste0("Ch", seq_len(n_channels))
  }

  # Calculate record parameters
  record_duration <- 1  # 1 second per record
  samples_per_record <- as.integer(sr)
  n_records <- ceiling(n_samples / samples_per_record)

  # Pad data if needed
  padded_samples <- n_records * samples_per_record
  if (padded_samples > n_samples) {
    padding <- matrix(0, nrow = padded_samples - n_samples, ncol = n_channels)
    data <- rbind(data, padding)
  }

  # Open file
  con <- file(path, "wb")
  on.exit(close(con))

  # Write main header
  .writeEDFHeader(con, patient_id, recording_id, n_channels, n_records, record_duration)

  # Write signal headers
  .writeEDFSignalHeaders(con, labels, n_channels, samples_per_record, data)

  # Write data
  .writeEDFData(con, data, n_channels, n_records, samples_per_record)

  invisible(NULL)
}

#' Write EDF main header
#' @noRd
.writeEDFHeader <- function(con, patient_id, recording_id, n_channels,
                            n_records, record_duration) {
  pad <- function(s, n) {
    s <- substr(s, 1, n)
    paste0(s, paste(rep(" ", n - nchar(s)), collapse = ""))
  }

  now <- Sys.time()

  writeBin(charToRaw(pad("0", 8)), con)  # Version
  writeBin(charToRaw(pad(patient_id, 80)), con)
  writeBin(charToRaw(pad(recording_id, 80)), con)
  writeBin(charToRaw(format(now, "%d.%m.%y")), con)  # Start date
  writeBin(charToRaw(format(now, "%H.%M.%S")), con)  # Start time
  writeBin(charToRaw(pad(as.character(256 + n_channels * 256), 8)), con)  # Header bytes
  writeBin(charToRaw(pad("", 44)), con)  # Reserved
  writeBin(charToRaw(pad(as.character(n_records), 8)), con)
  writeBin(charToRaw(pad(as.character(record_duration), 8)), con)
  writeBin(charToRaw(pad(as.character(n_channels), 4)), con)
}

#' Write EDF signal headers
#' @noRd
.writeEDFSignalHeaders <- function(con, labels, n_channels, samples_per_record, data) {
  pad <- function(s, n) {
    s <- substr(as.character(s), 1, n)
    paste0(s, paste(rep(" ", n - nchar(s)), collapse = ""))
  }

  # Calculate physical min/max per channel
  phys_min <- apply(data, 2, min, na.rm = TRUE)
  phys_max <- apply(data, 2, max, na.rm = TRUE)

  # Labels
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad(labels[i], 16)), con)
  # Transducer type
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("", 80)), con)
  # Physical dimension
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("uV", 8)), con)
  # Physical min
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad(sprintf("%.6g", phys_min[i]), 8)), con)
  # Physical max
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad(sprintf("%.6g", phys_max[i]), 8)), con)
  # Digital min
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("-32768", 8)), con)
  # Digital max
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("32767", 8)), con)
  # Prefiltering
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("", 80)), con)
  # Samples per record
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad(as.character(samples_per_record), 8)), con)
  # Reserved
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("", 32)), con)
}

#' Write EDF data records
#' @noRd
.writeEDFData <- function(con, data, n_channels, n_records, samples_per_record) {
  # Calculate scaling
  phys_min <- apply(data, 2, min, na.rm = TRUE)
  phys_max <- apply(data, 2, max, na.rm = TRUE)

  scale <- 65535 / (phys_max - phys_min)
  scale[!is.finite(scale)] <- 1

  for (rec in seq_len(n_records)) {
    start <- (rec - 1) * samples_per_record + 1
    end <- rec * samples_per_record

    for (ch in seq_len(n_channels)) {
      segment <- data[start:end, ch]
      # Scale to 16-bit integers
      digital <- as.integer(round((segment - phys_min[ch]) * scale[ch] - 32768))
      digital[digital < -32768L] <- -32768L
      digital[digital > 32767L] <- 32767L
      writeBin(digital, con, size = 2L, endian = "little")
    }
  }
}

#' Write BDF (BioSemi Data Format) file
#'
#' Writes a PhysioExperiment object to BDF format (24-bit resolution).
#'
#' @param x A PhysioExperiment object.
#' @param path Output file path.
#' @param patient_id Patient identification string.
#' @param recording_id Recording identification string.
#' @return Invisible NULL.
#' @details
#' BDF is a 24-bit extension of EDF providing higher resolution than the
#' standard 16-bit EDF format. It is commonly used with BioSemi acquisition
#' systems but can be used for any high-resolution physiological data.
#' @export
#' @examples
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
#'   colData = S4Vectors::DataFrame(label = paste0("Ch", 1:10)),
#'   samplingRate = 100
#' )
#' tmp <- tempfile(fileext = ".bdf")
#' writeBDF(pe, tmp)
#' unlink(tmp)
writeBDF <- function(x, path, patient_id = "X", recording_id = "X") {
  stopifnot(inherits(x, "PhysioExperiment"))

  sr <- samplingRate(x)
  if (is.na(sr) || sr <= 0) {
    stop("Valid sampling rate required for BDF export", call. = FALSE)
  }

  assay_name <- defaultAssay(x)
  data <- SummarizedExperiment::assay(x, assay_name)
  dims <- dim(data)

  # Handle 3D arrays with single sample
  if (length(dims) == 3 && dims[3] == 1) {
    data <- data[, , 1, drop = TRUE]
    dims <- dim(data)
  }

  if (length(dims) != 2) {
    stop("Only 2D data can be exported to BDF", call. = FALSE)
  }

  n_samples <- dims[1]
  n_channels <- dims[2]

  # Get channel labels
  col_data <- SummarizedExperiment::colData(x)
  if ("label" %in% names(col_data)) {
    labels <- as.character(col_data$label)
  } else {
    labels <- paste0("Ch", seq_len(n_channels))
  }

  # Calculate record parameters
  record_duration <- 1
  samples_per_record <- as.integer(sr)
  n_records <- ceiling(n_samples / samples_per_record)

  # Pad data if needed
  padded_samples <- n_records * samples_per_record
  if (padded_samples > n_samples) {
    padding <- matrix(0, nrow = padded_samples - n_samples, ncol = n_channels)
    data <- rbind(data, padding)
  }

  # Open file
  con <- file(path, "wb")
  on.exit(close(con))

  # Write BDF header (same as EDF but starts with 0xFF and "BIOSEMI")
  .writeBDFHeader(con, patient_id, recording_id, n_channels, n_records, record_duration)

  # Write signal headers (same as EDF but with 24-bit digital range)
  .writeBDFSignalHeaders(con, labels, n_channels, samples_per_record, data)

  # Write data as 24-bit
  .writeBDFData(con, data, n_channels, n_records, samples_per_record)

  invisible(NULL)
}

#' Write BDF main header
#' @noRd
.writeBDFHeader <- function(con, patient_id, recording_id, n_channels,
                            n_records, record_duration) {
  pad <- function(s, n) {
    s <- substr(s, 1, n)
    paste0(s, paste(rep(" ", n - nchar(s)), collapse = ""))
  }

  now <- Sys.time()

  # BDF starts with 0xFF followed by "BIOSEMI" (total 8 bytes)
  writeBin(as.raw(0xFF), con)
  writeBin(charToRaw("BIOSEMI"), con)

  writeBin(charToRaw(pad(patient_id, 80)), con)
  writeBin(charToRaw(pad(recording_id, 80)), con)
  writeBin(charToRaw(format(now, "%d.%m.%y")), con)
  writeBin(charToRaw(format(now, "%H.%M.%S")), con)
  writeBin(charToRaw(pad(as.character(256 + n_channels * 256), 8)), con)
  writeBin(charToRaw(pad("24BIT", 44)), con)  # Reserved field indicates 24-bit
  writeBin(charToRaw(pad(as.character(n_records), 8)), con)
  writeBin(charToRaw(pad(as.character(record_duration), 8)), con)
  writeBin(charToRaw(pad(as.character(n_channels), 4)), con)
}

#' Write BDF signal headers
#' @noRd
.writeBDFSignalHeaders <- function(con, labels, n_channels, samples_per_record, data) {
  pad <- function(s, n) {
    s <- substr(as.character(s), 1, n)
    paste0(s, paste(rep(" ", n - nchar(s)), collapse = ""))
  }

  # Calculate physical min/max per channel
  phys_min <- apply(data, 2, min, na.rm = TRUE)
  phys_max <- apply(data, 2, max, na.rm = TRUE)

  # Labels
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad(labels[i], 16)), con)
  # Transducer type
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("Active Electrode", 80)), con)
  # Physical dimension
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("uV", 8)), con)
  # Physical min
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad(sprintf("%.6g", phys_min[i]), 8)), con)
  # Physical max
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad(sprintf("%.6g", phys_max[i]), 8)), con)
  # Digital min (24-bit: -8388608)
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("-8388608", 8)), con)
  # Digital max (24-bit: 8388607)
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("8388607", 8)), con)
  # Prefiltering
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("", 80)), con)
  # Samples per record
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad(as.character(samples_per_record), 8)), con)
  # Reserved
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("", 32)), con)
}

#' Write BDF data records (24-bit)
#' @noRd
.writeBDFData <- function(con, data, n_channels, n_records, samples_per_record) {
  # Calculate scaling for 24-bit range
  phys_min <- apply(data, 2, min, na.rm = TRUE)
  phys_max <- apply(data, 2, max, na.rm = TRUE)

  # Scale to 24-bit range (16777215 = 2^24 - 1)
  scale <- 16777215 / (phys_max - phys_min)
  scale[!is.finite(scale)] <- 1

  for (rec in seq_len(n_records)) {
    start <- (rec - 1) * samples_per_record + 1
    end <- rec * samples_per_record

    for (ch in seq_len(n_channels)) {
      segment <- data[start:end, ch]
      # Scale to 24-bit signed integers
      digital <- as.integer(round((segment - phys_min[ch]) * scale[ch] - 8388608))
      digital[digital < -8388608L] <- -8388608L
      digital[digital > 8388607L] <- 8388607L

      # Write as 24-bit little-endian (3 bytes per sample)
      for (val in digital) {
        # Convert to unsigned for byte manipulation
        if (val < 0) val <- val + 16777216L
        b1 <- as.raw(val %% 256L)
        b2 <- as.raw((val %/% 256L) %% 256L)
        b3 <- as.raw((val %/% 65536L) %% 256L)
        writeBin(c(b1, b2, b3), con)
      }
    }
  }
}

#' Read BDF (BioSemi Data Format) file
#'
#' Reads a BDF file and returns a PhysioExperiment object.
#' BDF is a 24-bit extension of the EDF format used by BioSemi systems.
#'
#' @param path Path to the BDF file.
#' @param channels Optional character vector of channel names to load.
#'   If NULL, all channels are loaded.
#' @param start_time Optional start time in seconds for reading a subset. Note
#'   that BDF subsetting is record-granular: \code{start_time}/\code{end_time}
#'   are rounded outward to whole data records (typically 1 s), so the returned
#'   signal and any extracted trigger onsets share that record-aligned window
#'   (onsets are relative to it and may extend slightly past \code{end_time}).
#' @param end_time Optional end time in seconds for reading a subset.
#' @param resample Logical. If \code{FALSE} (default) and channels have
#'   differing native rates, a \code{MultiRatePhysioExperiment} is returned; if
#'   \code{TRUE}, all channels are resampled to the highest rate (legacy).
#' @param status Logical. If \code{TRUE} (default) and a BioSemi \code{"Status"}
#'   channel is present, stimulus triggers are extracted from it (see
#'   \code{\link{bdfTriggerEvents}}) and attached to the result as events.
#' @return A \code{PhysioExperiment}, or a
#'   \code{\link[PhysioCore]{MultiRatePhysioExperiment}} when native rates differ
#'   and \code{resample = FALSE}.
#' @details
#' BDF (BioSemi Data Format) is a 24-bit variant of EDF used by BioSemi
#' acquisition systems. The main differences from EDF are:
#' - 24-bit data resolution (vs 16-bit in EDF)
#' - Header starts with 0xFF followed by "BIOSEMI"
#' - Digital range is -8388608 to 8388607
#' @export
#' @examples
#' # Round-trip a small recording through a temporary BDF file
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
#'   colData = S4Vectors::DataFrame(label = c("A1", "A2", "B1", "B2")),
#'   samplingRate = 100
#' )
#' tmp <- tempfile(fileext = ".bdf")
#' writeBDF(pe, tmp)
#'
#' # Read the file back
#' pe_in <- readBDF(tmp)
#'
#' # Read only specific channels
#' pe_sub <- readBDF(tmp, channels = c("A1", "B1"))
#'
#' unlink(tmp)
readBDF <- function(path, channels = NULL, start_time = NULL, end_time = NULL,
                    resample = FALSE, status = TRUE) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  # Open file in binary mode
  con <- file(path, "rb")
  on.exit(close(con))

  # Verify BDF format (first byte is 0xFF)
  first_byte <- readBin(con, "raw", 1)
  if (first_byte != as.raw(0xFF)) {
    stop("Not a valid BDF file: expected 0xFF header byte", call. = FALSE)
  }
  seek(con, 0)

  # Read header (same structure as EDF)
  header <- .parseEDFHeader(con)

  # Read signal headers
  ns <- header$num_signals
  signal_headers <- .parseEDFSignalHeaders(con, ns)

  # Determine which channels to read
  if (!is.null(channels)) {
    channel_idx <- match(channels, signal_headers$label)
    if (any(is.na(channel_idx))) {
      missing <- channels[is.na(channel_idx)]
      stop("Channels not found: ", paste(missing, collapse = ", "), call. = FALSE)
    }
  } else {
    # Exclude Status channel commonly found in BDF
    channel_idx <- which(!signal_headers$label %in% c("Status", "EDF Annotations"))
    if (length(channel_idx) == 0) channel_idx <- seq_len(ns)
  }

  # Calculate data parameters
  n_records <- header$num_data_records
  record_duration <- header$data_record_duration
  total_duration <- n_records * record_duration

  # Calculate which records to read based on start_time/end_time
  start_record <- 1L
  end_record <- n_records

  if (!is.null(start_time)) {
    if (start_time < 0) start_time <- 0
    if (start_time >= total_duration) {
      stop("start_time exceeds recording duration", call. = FALSE)
    }
    start_record <- max(1L, as.integer(floor(start_time / record_duration)) + 1L)
  }

  if (!is.null(end_time)) {
    if (end_time > total_duration) end_time <- total_duration
    if (end_time <= 0 || (!is.null(start_time) && end_time <= start_time)) {
      stop("Invalid end_time", call. = FALSE)
    }
    end_record <- min(n_records, as.integer(ceiling(end_time / record_duration)))
  }

  # Read data records (BDF uses 24-bit data)
  data_list <- .readBDFData(con, signal_headers, n_records, channel_idx,
                            start_record = start_record, end_record = end_record)

  close(con)
  on.exit(NULL)

  # Build the container. Differing native rates yield a
  # MultiRatePhysioExperiment unless resample = TRUE.
  selected_headers <- lapply(signal_headers, function(x) x[channel_idx])
  sample_rates <- selected_headers$samples_per_record / record_duration

  meta <- list(
    patient_id = header$patient_id,
    recording_id = header$recording_id,
    start_date = header$start_date,
    start_time = header$start_time,
    file_type = "BDF",
    original_file = path
  )

  result <- .assembleEDFStreams(data_list, sample_rates, selected_headers, meta,
                                resample = resample)

  # extract stimulus triggers from the BioSemi Status channel as events
  # (aligned to the same record range as the signal read)
  if (isTRUE(status) && "Status" %in% signal_headers$label) {
    result <- .attachBDFTriggers(result, path, start_record, end_record)
  }
  result
}

#' Read BDF data records (24-bit)
#' @noRd
.readBDFData <- function(con, signal_headers, n_records, channel_idx,
                         start_record = 1L, end_record = NULL) {
  ns <- length(signal_headers$label)
  samples_per_record <- signal_headers$samples_per_record

  if (is.null(end_record)) end_record <- n_records
  records_to_read <- end_record - start_record + 1L

  # Initialize data lists
  data_list <- lapply(channel_idx, function(i) {
    numeric(records_to_read * samples_per_record[i])
  })

  # Calculate scaling factors
  scale <- (signal_headers$physical_max - signal_headers$physical_min) /
           (signal_headers$digital_max - signal_headers$digital_min)
  offset <- signal_headers$physical_min - scale * signal_headers$digital_min

  # Skip records before start_record (3 bytes per sample for BDF)
  if (start_record > 1) {
    bytes_per_record <- sum(samples_per_record * 3)
    skip_bytes <- (start_record - 1) * bytes_per_record
    seek(con, seek(con) + skip_bytes)
  }

  # Read data records
  for (rec in seq_len(records_to_read)) {
    for (sig in seq_len(ns)) {
      n_samples <- samples_per_record[sig]
      # BDF uses 24-bit (3 bytes) little-endian signed integers
      raw_bytes <- readBin(con, "raw", n_samples * 3)
      raw_data <- .convert24bitToInteger(raw_bytes, n_samples)

      if (sig %in% channel_idx) {
        idx <- which(channel_idx == sig)
        start <- (rec - 1) * n_samples + 1
        end <- rec * n_samples
        # Convert to physical values
        data_list[[idx]][start:end] <- raw_data * scale[sig] + offset[sig]
      }
    }
  }

  data_list
}

#' Convert 24-bit little-endian bytes to integers
#' @noRd
.convert24bitToInteger <- function(raw_bytes, n_samples) {
  result <- numeric(n_samples)
  for (i in seq_len(n_samples)) {
    idx <- (i - 1) * 3
    b1 <- as.integer(raw_bytes[idx + 1])
    b2 <- as.integer(raw_bytes[idx + 2])
    b3 <- as.integer(raw_bytes[idx + 3])
    # Little-endian 24-bit signed integer
    value <- b1 + b2 * 256L + b3 * 65536L
    # Handle sign (if MSB of b3 is set, value is negative)
    if (b3 >= 128L) {
      value <- value - 16777216L
    }
    result[i] <- value
  }
  result
}
