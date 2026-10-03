# FIF / FIFF (Functional Image File Format) reader for Elekta/Neuromag/MNE raw
# data. A FIFF file is a big-endian stream of tags; each tag is a 16-byte header
# (kind, type, size, next : all int32) followed by `size` data bytes. This
# implements a native tag-stream parser for the common raw-data tags, with an
# optional reticulate + mne.io.read_raw_fif fallback for files the native path
# cannot handle (e.g. compressed / matrix-coded buffers). The mne bridge here is
# a minimal inline conversion; DMIO-15's fromMNE() will supersede it.

# ---- FIFF constants ---------------------------------------------------------

.FIFF <- list(
  FILE_ID = 100L, DIR_POINTER = 101L, DIR = 102L,
  BLOCK_START = 104L, BLOCK_END = 105L,
  NCHAN = 200L, SFREQ = 201L, CH_INFO = 203L, FIRST_SAMPLE = 208L,
  LOWPASS = 219L, HIGHPASS = 223L, DATA_BUFFER = 300L,
  # data types
  T_SHORT = 2L, T_INT = 3L, T_FLOAT = 4L, T_DOUBLE = 5L,
  T_DAU_PACK16 = 16L, T_CH_INFO_STRUCT = 30L)

# channel kind (FIFFV_*_CH) -> a PhysioExperiment channel type label
.fif_ch_type <- function(kind) {
  switch(as.character(kind),
    "1" = "meg", "2" = "eeg", "3" = "stim", "102" = "bio", "201" = "mcg",
    "202" = "eog", "301" = "ref_meg", "302" = "emg", "402" = "ecg",
    "502" = "misc", "602" = "resp", "unknown")
}

# unit (FIFF_UNIT_*) -> a unit string
.fif_unit_str <- function(unit) {
  switch(as.character(unit),
    "107" = "V", "112" = "T", "201" = "T/m", "202" = "Am", "-1" = "none", "n/a")
}

# ---- native tag-stream parser -----------------------------------------------

# Read the FIFF tag stream sequentially (tags are stored contiguously).
.read_fif_tags <- function(path) {
  con <- file(path, "rb"); on.exit(close(con))
  fsize <- file.info(path)$size
  tags <- list()
  repeat {
    pos <- seek(con)
    if (pos + 16 > fsize) break
    hdr <- readBin(con, "integer", 4L, size = 4L, endian = "big")
    if (length(hdr) < 4L) break
    kind <- hdr[1]; type <- hdr[2]; size <- hdr[3]; nxt <- hdr[4]
    if (size < 0 || pos + 16 + size > fsize) break
    data <- if (size > 0) readBin(con, "raw", size) else raw(0)
    tags[[length(tags) + 1L]] <- list(kind = kind, type = type,
                                      size = size, nxt = nxt, data = data)
  }
  tags
}

# Decode a FIFF fixed-width string field (e.g. a channel name). FIFF strings are
# Latin-1 and NUL-terminated within a fixed-size field, and the bytes after the
# terminator are unspecified padding. Take the bytes up to the first NUL, decode
# them as Latin-1, and normalise to UTF-8. This drops post-terminator garbage
# and guarantees a valid-UTF-8 result, so downstream regex on the name (trimws,
# which is sub(perl = TRUE)) never hits an "invalid UTF-8" error on real files.
.fif_decode_str <- function(raw_bytes) {
  nul <- which(raw_bytes == as.raw(0L))
  if (length(nul)) {
    raw_bytes <- if (nul[1L] > 1L) raw_bytes[seq_len(nul[1L] - 1L)] else raw(0L)
  }
  if (!length(raw_bytes)) return("")
  s <- rawToChar(raw_bytes)
  Encoding(s) <- "latin1"
  enc2utf8(s)
}

# Decode a 96-byte FIFFT_CH_INFO_STRUCT (big-endian).
.parse_ch_info <- function(d) {
  gi <- function(off) readBin(d[(off + 1L):(off + 4L)], "integer", 1L,
                              size = 4L, endian = "big")
  gf <- function(off) readBin(d[(off + 1L):(off + 4L)], "double", 1L,
                              size = 4L, endian = "big")
  list(kind = gi(8L), range = gf(12L), cal = gf(16L),
       unit = gi(72L), unit_mul = gi(76L),
       name = trimws(.fif_decode_str(d[81:96])))
}

# Decode a raw data buffer to a numeric vector.
.decode_fif_buffer <- function(d, type) {
  base <- bitwAnd(type, 0xFFFFL)             # strip any matrix-coding flags
  switch(as.character(base),
    "2" = , "16" = readBin(d, "integer", length(d) %/% 2L, size = 2L,
                           signed = TRUE, endian = "big"),
    "3" = readBin(d, "integer", length(d) %/% 4L, size = 4L, endian = "big"),
    "4" = readBin(d, "double", length(d) %/% 4L, size = 4L, endian = "big"),
    "5" = readBin(d, "double", length(d) %/% 8L, size = 8L, endian = "big"),
    stop(sprintf("unsupported FIFF data-buffer type %d", base), call. = FALSE))
}

.readFIFNative <- function(path) {
  tags <- .read_fif_tags(path)
  if (length(tags) == 0L || tags[[1]]$kind != .FIFF$FILE_ID) {
    stop("not a FIFF file (missing FILE_ID tag)", call. = FALSE)
  }
  nchan <- NULL; sfreq <- NULL; first_samp <- 0L
  lowpass <- NA_real_; highpass <- NA_real_
  chs <- list(); buffers <- list()
  for (tg in tags) {
    k <- tg$kind
    if (k == .FIFF$NCHAN) {
      nchan <- readBin(tg$data, "integer", 1L, size = 4L, endian = "big")
    } else if (k == .FIFF$SFREQ) {
      sfreq <- readBin(tg$data, "double", 1L, size = 4L, endian = "big")
    } else if (k == .FIFF$CH_INFO) {
      chs[[length(chs) + 1L]] <- .parse_ch_info(tg$data)
    } else if (k == .FIFF$FIRST_SAMPLE) {
      first_samp <- readBin(tg$data, "integer", 1L, size = 4L, endian = "big")
    } else if (k == .FIFF$LOWPASS) {
      lowpass <- readBin(tg$data, "double", 1L, size = 4L, endian = "big")
    } else if (k == .FIFF$HIGHPASS) {
      highpass <- readBin(tg$data, "double", 1L, size = 4L, endian = "big")
    } else if (k == .FIFF$DATA_BUFFER) {
      buffers[[length(buffers) + 1L]] <- .decode_fif_buffer(tg$data, tg$type)
    }
  }
  if (is.null(nchan)) stop("FIFF file has no FIFF_NCHAN tag", call. = FALSE)
  if (is.null(sfreq) || !is.finite(sfreq) || sfreq <= 0) {
    stop("FIFF file has no valid FIFF_SFREQ tag", call. = FALSE)
  }
  if (length(chs) != nchan) {
    stop(sprintf("FIFF channel-info count (%d) does not match nchan (%d)",
                 length(chs), nchan), call. = FALSE)
  }
  if (length(buffers) == 0L) stop("FIFF file has no data buffers", call. = FALSE)

  # Reshape each buffer independently (raw buffers are sample-major, channels
  # varying fastest) and cbind the blocks. Validating alignment per buffer stops
  # a mis-sized/corrupt buffer from silently shearing the channel grid.
  blocks <- lapply(buffers, function(b) {
    if (length(b) %% nchan != 0L) {
      stop(sprintf(paste0("a FIFF data buffer holds %d values, not a multiple ",
                          "of nchan (%d); the file may be truncated or corrupt"),
                   length(b), nchan), call. = FALSE)
    }
    matrix(b, nrow = nchan)                    # nchan x (buffer samples)
  })
  raw_mat <- do.call(cbind, blocks)            # nchan x total nsamp

  cals <- vapply(chs, function(c) c$range * c$cal, numeric(1))
  cals[!is.finite(cals) | cals == 0] <- 1
  phys <- t(raw_mat * cals)                    # per-channel calibration; nsamp x nchan

  labels <- vapply(chs, `[[`, character(1), "name")
  labels[!nzchar(labels)] <- paste0("ch", which(!nzchar(labels)))
  col_data <- S4Vectors::DataFrame(
    label = labels,
    type = vapply(chs, function(c) .fif_ch_type(c$kind), character(1)),
    unit = vapply(chs, function(c) .fif_unit_str(c$unit), character(1)),
    cal = cals)
  colnames(phys) <- labels

  PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = phys),
    colData = col_data,
    metadata = list(source_format = "FIF", fif_first_sample = first_samp,
                    lowpass = lowpass, highpass = highpass),
    samplingRate = sfreq)
}

# ---- reticulate + mne fallback (gated) --------------------------------------

.readFIFmne <- function(path) {
  if (!requireNamespace("reticulate", quietly = TRUE) ||
      !reticulate::py_module_available("mne")) {
    stop("the FIFF mne fallback requires the Python 'mne' module via reticulate",
         call. = FALSE)
  }
  mne <- reticulate::import("mne", delay_load = TRUE)
  raw <- mne$io$read_raw_fif(path, preload = TRUE, verbose = FALSE)
  info <- raw$info
  data <- t(reticulate::py_to_r(raw$get_data()))       # (nchan, nsamp) -> nsamp x nchan
  ch_names <- as.character(reticulate::py_to_r(info$ch_names))
  ch_types <- as.character(reticulate::py_to_r(raw$get_channel_types()))
  sfreq <- as.numeric(reticulate::py_to_r(info$`__getitem__`("sfreq")))
  colnames(data) <- ch_names
  PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = data),
    colData = S4Vectors::DataFrame(label = ch_names, type = ch_types),
    metadata = list(source_format = "FIF", backend = "mne"),
    samplingRate = sfreq)
}

#' Read an Elekta/Neuromag/MNE FIF (FIFF) file
#'
#' Reads a raw FIFF file into a \code{PhysioExperiment}. The native parser reads
#' the FIFF tag stream directly (channel info, sampling rate and data buffers).
#' For files the native path cannot handle, and when the Python \pkg{mne} module
#' is available through \pkg{reticulate}, it can fall back to
#' \code{mne.io.read_raw_fif()}.
#'
#' @param path Path to a \code{.fif} file.
#' @param backend One of \code{"auto"} (native, then mne on failure),
#'   \code{"native"} (native only), or \code{"mne"} (force the reticulate/mne
#'   path).
#' @return A \code{PhysioExperiment} with calibrated signal values in the
#'   \code{"raw"} assay, channel labels/types/units in \code{colData}, and the
#'   sampling rate set.
#' @references FIFF file format (Elekta Neuromag); MNE-Python read_raw_fif.
#' @seealso \code{\link{readEDF}}, \code{\link{readBDF}}
#' @export
readFIF <- function(path, backend = c("auto", "native", "mne")) {
  backend <- match.arg(backend)
  if (!file.exists(path)) stop("File not found: ", path, call. = FALSE)
  if (backend == "mne") return(.readFIFmne(path))
  native <- tryCatch(.readFIFNative(path), error = function(e) e)
  if (methods::is(native, "PhysioExperiment")) return(native)
  if (backend == "native") stop(native)
  # auto: native failed - try mne, but surface the native error if mne is absent
  tryCatch(.readFIFmne(path), error = function(mne_err) {
    stop(sprintf("native FIFF read failed (%s) and the mne fallback is unavailable (%s)",
                 conditionMessage(native), conditionMessage(mne_err)), call. = FALSE)
  })
}
