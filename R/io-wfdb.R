# WFDB (WaveForm DataBase) record I/O: the format used by PhysioNet databases
# such as MIT-BIH, QT-DB and LUDB (Moody & Mark). A record is a text header
# (.hea) describing the signals plus one binary signal file (.dat) holding the
# interleaved samples, and optional annotation files (.atr/.qrs/.pu...).
# Supported signal storage formats: 16, 61, 80, 212, 24, 32.

# ---- MIT annotation code <-> symbol map (Moody & Mark) ----------------------

.WFDB_ANN_CODES <- c(
  "0" = "",  "1" = "N", "2" = "L", "3" = "R", "4" = "a", "5" = "V", "6" = "F",
  "7" = "J", "8" = "A", "9" = "S", "10" = "E", "11" = "j", "12" = "/",
  "13" = "Q", "14" = "~", "16" = "|", "18" = "s", "19" = "T", "20" = "*",
  "21" = "D", "22" = "\"", "23" = "=", "24" = "p", "25" = "B", "26" = "^",
  "27" = "t", "28" = "+", "29" = "u", "30" = "?", "31" = "!", "32" = "[",
  "33" = "]", "34" = "e", "35" = "n", "36" = "@", "37" = "x", "38" = "f",
  "39" = "(", "40" = ")", "41" = "r")

.wfdb_symbol <- function(code) {
  s <- .WFDB_ANN_CODES[as.character(code)]
  ifelse(is.na(s), "?", unname(s))
}

.wfdb_code <- function(symbol) {
  tbl <- .WFDB_ANN_CODES[.WFDB_ANN_CODES != ""]   # drop NOTQRS (code 0 / "")
  m <- match(symbol, tbl)
  code <- as.integer(names(tbl)[m])
  code[is.na(code)] <- 13L                  # empty/unknown -> Q (never code 0)
  code
}

# ---- header (.hea) ----------------------------------------------------------

.parse_hea <- function(path) {
  lines <- readLines(path, warn = FALSE)
  lines <- lines[!grepl("^\\s*#", lines) & nzchar(trimws(lines))]
  rec <- strsplit(trimws(lines[1]), "\\s+")[[1]]
  name <- rec[1]
  nsig <- as.integer(rec[2])
  fs <- if (length(rec) >= 3) as.numeric(sub("/.*", "", rec[3])) else 250
  nsamp <- if (length(rec) >= 4) as.integer(rec[4]) else NA_integer_

  sig <- vector("list", nsig)
  for (i in seq_len(nsig)) {
    f <- strsplit(trimws(lines[1 + i]), "\\s+")[[1]]
    file <- f[1]
    if (grepl("[x+]", f[2])) {
      stop("readWFDB does not support samples-per-frame (x) or byte-offset (+) ",
           "format modifiers in the signal spec", call. = FALSE)
    }
    fmt <- as.integer(sub("[x:+].*", "", f[2]))
    gain_field <- if (length(f) >= 3) f[3] else "200"
    gain <- as.numeric(sub("[(/].*", "", gain_field))
    if (is.na(gain) || gain == 0) gain <- 200
    baseline <- suppressWarnings(as.numeric(
      sub(".*\\(([-0-9]+)\\).*", "\\1", gain_field)))
    units <- if (grepl("/", gain_field)) sub(".*/", "", gain_field) else "mV"
    adcres <- if (length(f) >= 4) as.integer(f[4]) else 12L
    adczero <- if (length(f) >= 5) as.integer(f[5]) else 0L
    if (is.na(baseline)) baseline <- adczero
    desc <- if (length(f) >= 9) paste(f[9:length(f)], collapse = " ")
            else paste0("sig", i)
    sig[[i]] <- list(file = file, fmt = fmt, gain = gain, baseline = baseline,
                     units = units, adcres = adcres, adczero = adczero,
                     desc = desc)
  }
  list(name = name, nsig = nsig, fs = fs, nsamp = nsamp, signals = sig)
}

# ---- signal-format decoders (raw bytes -> integer sample vector) ------------

.decode_wfdb <- function(bytes, fmt, n) {
  switch(as.character(fmt),
    "16" = readBin(bytes, "integer", n, size = 2L, signed = TRUE, endian = "little"),
    "61" = readBin(bytes, "integer", n, size = 2L, signed = TRUE, endian = "big"),
    "32" = readBin(bytes, "integer", n, size = 4L, signed = TRUE, endian = "little"),
    "80" = as.integer(bytes[seq_len(n)]) - 128L,
    "24" = {
      b <- as.integer(bytes)
      i <- seq_len(n)
      v <- b[(i - 1) * 3 + 1] + bitwShiftL(b[(i - 1) * 3 + 2], 8) +
           bitwShiftL(b[(i - 1) * 3 + 3], 16)
      ifelse(v >= 8388608L, v - 16777216L, v)
    },
    "212" = .decode212(as.integer(bytes), n),
    stop(sprintf("unsupported WFDB format: %s", fmt), call. = FALSE))
}

.decode212 <- function(b, n) {
  out <- integer(n)
  npair <- n %/% 2L
  if (npair > 0) {
    k <- seq_len(npair)
    b0 <- b[(k - 1) * 3 + 1]; b1 <- b[(k - 1) * 3 + 2]; b2 <- b[(k - 1) * 3 + 3]
    s1 <- b0 + bitwShiftL(bitwAnd(b1, 15L), 8)
    s2 <- b2 + bitwShiftL(bitwShiftR(b1, 4), 8)
    out[(k - 1) * 2 + 1] <- ifelse(s1 > 2047L, s1 - 4096L, s1)
    out[(k - 1) * 2 + 2] <- ifelse(s2 > 2047L, s2 - 4096L, s2)
  }
  if (n %% 2L == 1L) {
    base <- npair * 3
    s1 <- b[base + 1] + bitwShiftL(bitwAnd(b[base + 2], 15L), 8)
    out[n] <- if (s1 > 2047L) s1 - 4096L else s1
  }
  out
}

# ---- signal-format encoders (integer sample vector -> raw bytes) ------------

.encode_wfdb <- function(vals, fmt) {
  switch(as.character(fmt),
    "16" = writeBin(as.integer(vals), raw(), size = 2L, endian = "little"),
    "61" = writeBin(as.integer(vals), raw(), size = 2L, endian = "big"),
    "32" = writeBin(as.integer(vals), raw(), size = 4L, endian = "little"),
    "80" = as.raw(bitwAnd(as.integer(vals) + 128L, 255L)),
    "24" = {
      v <- bitwAnd(as.integer(vals), 16777215L)
      as.raw(as.vector(rbind(bitwAnd(v, 255L),
                             bitwAnd(bitwShiftR(v, 8), 255L),
                             bitwAnd(bitwShiftR(v, 16), 255L))))
    },
    "212" = .encode212(as.integer(vals)),
    stop(sprintf("unsupported WFDB format: %s", fmt), call. = FALSE))
}

.encode212 <- function(vals) {
  n <- length(vals)
  out <- raw(ceiling(n / 2) * 3)
  npair <- n %/% 2L
  if (npair > 0) {
    k <- seq_len(npair)
    s1 <- bitwAnd(vals[(k - 1) * 2 + 1], 4095L)
    s2 <- bitwAnd(vals[(k - 1) * 2 + 2], 4095L)
    out[(k - 1) * 3 + 1] <- as.raw(bitwAnd(s1, 255L))
    out[(k - 1) * 3 + 2] <- as.raw(bitwOr(bitwShiftR(s1, 8),
                                          bitwShiftL(bitwShiftR(s2, 8), 4)))
    out[(k - 1) * 3 + 3] <- as.raw(bitwAnd(s2, 255L))
  }
  if (n %% 2L == 1L) {
    base <- npair * 3
    s1 <- bitwAnd(vals[n], 4095L)
    out[base + 1] <- as.raw(bitwAnd(s1, 255L))
    out[base + 2] <- as.raw(bitwShiftR(s1, 8))
  }
  out
}

.wfdb_bytes_per_frame <- function(fmt, nsig) {
  switch(as.character(fmt),
    "16" = , "61" = 2L * nsig, "80" = nsig, "32" = 4L * nsig,
    "24" = 3L * nsig, "212" = NA_integer_,   # 212 is bit-packed across signals
    stop("unsupported format", call. = FALSE))
}

#' Read a WFDB record
#'
#' Reads a WFDB record's header (\code{.hea}) and interleaved signal file
#' (\code{.dat}) into a \code{PhysioExperiment}. Storage formats 16, 61, 80,
#' 212, 24 and 32 are supported.
#'
#' @param record Path to the record with or without extension (e.g.
#'   \code{"path/to/100"} or \code{"path/to/100.hea"}).
#' @return A \code{PhysioExperiment} with physical signal values in the
#'   \code{"raw"} assay, channel labels/units/gain in \code{colData}, and the
#'   sampling rate set.
#' @references Moody, G. B. & Mark, R. G. (2001). The impact of the MIT-BIH
#'   Arrhythmia Database. \emph{IEEE Eng. Med. Biol.}, 20(3), 45-50.
#' @seealso \code{\link{writeWFDB}}, \code{\link{readWFDBAnnotation}}
#' @export
readWFDB <- function(record) {
  hea <- sub("\\.hea$", "", record)
  hea <- paste0(hea, ".hea")
  if (!file.exists(hea)) stop("header not found: ", hea, call. = FALSE)
  h <- .parse_hea(hea)

  dir <- dirname(hea)
  files <- vapply(h$signals, `[[`, character(1), "file")
  fmts <- vapply(h$signals, `[[`, integer(1), "fmt")
  if (length(unique(files)) != 1L || length(unique(fmts)) != 1L) {
    stop("readWFDB supports single-file, single-format records", call. = FALSE)
  }
  dat <- file.path(dir, files[1])
  if (!file.exists(dat)) stop("signal file not found: ", dat, call. = FALSE)

  bytes <- readBin(dat, "raw", file.info(dat)$size)
  if (is.na(h$nsamp)) {                             # nsamp is optional in .hea
    bpf <- .wfdb_bytes_per_frame(fmts[1], h$nsig)
    h$nsamp <- if (is.na(bpf)) (length(bytes) %/% (3L * h$nsig)) * 2L  # 212
               else length(bytes) %/% bpf
  }
  ntot <- h$nsamp * h$nsig
  flat <- .decode_wfdb(bytes, fmts[1], ntot)
  raw_mat <- t(matrix(flat, nrow = h$nsig, ncol = h$nsamp))   # nsamp x nsig

  phys <- matrix(0, h$nsamp, h$nsig)
  for (i in seq_len(h$nsig)) {
    phys[, i] <- (raw_mat[, i] - h$signals[[i]]$baseline) / h$signals[[i]]$gain
  }
  labels <- vapply(h$signals, `[[`, character(1), "desc")
  colnames(phys) <- labels
  col_data <- S4Vectors::DataFrame(
    label = labels,
    unit = vapply(h$signals, `[[`, character(1), "units"),
    gain = vapply(h$signals, `[[`, numeric(1), "gain"),
    baseline = vapply(h$signals, function(s) as.numeric(s$baseline), numeric(1)),
    format = fmts)

  PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = phys),
    colData = col_data,
    metadata = list(wfdb_record = h$name, wfdb_format = fmts[1]),
    samplingRate = h$fs)
}

#' Write a WFDB record
#'
#' Writes a \code{PhysioExperiment} to a WFDB record (\code{.hea} + \code{.dat}).
#'
#' @param x A \code{PhysioExperiment} (2D \code{"raw"} assay of physical values).
#' @param record Output record path (without extension).
#' @param format WFDB storage format: one of 16, 61, 80, 212, 24, 32.
#' @param gain ADC gain (units per ADU); a scalar or one per channel.
#' @param baseline ADC baseline value (raw value for 0 physical); scalar or per
#'   channel.
#' @return \code{record}, invisibly.
#' @seealso \code{\link{readWFDB}}
#' @export
writeWFDB <- function(x, record, format = 16L, gain = 200, baseline = 0) {
  stopifnot(inherits(x, "PhysioExperiment"))
  data <- as.matrix(SummarizedExperiment::assay(x, defaultAssay(x)))
  if (length(dim(data)) != 2L) stop("only 2D signals can be written", call. = FALSE)
  nsamp <- nrow(data); nsig <- ncol(data)
  fs <- samplingRate(x)
  gain <- rep(gain, length.out = nsig)
  baseline <- rep(baseline, length.out = nsig)
  labels <- channelNames(x)
  if (length(labels) != nsig) labels <- paste0("sig", seq_len(nsig))

  # quantize to integer ADUs, interleave frame-major
  raw_mat <- matrix(0, nsamp, nsig)
  for (i in seq_len(nsig)) {
    raw_mat[, i] <- round(data[, i] * gain[i] + baseline[i])
  }
  # reject values outside the format's storage range (silent wrap = corruption)
  lim <- switch(as.character(format),
    "16" = , "61" = c(-32768, 32767), "32" = c(-2147483648, 2147483647),
    "80" = c(-128, 127), "212" = c(-2048, 2047), "24" = c(-8388608, 8388607),
    c(-32768, 32767))
  if (any(raw_mat < lim[1] | raw_mat > lim[2], na.rm = TRUE)) {
    stop(sprintf(paste0("ADU values out of range [%g, %g] for WFDB format %s; ",
                        "adjust gain/baseline"), lim[1], lim[2], format),
         call. = FALSE)
  }
  flat <- as.integer(t(raw_mat))                    # frame-major
  bytes <- .encode_wfdb(flat, format)
  datfile <- paste0(basename(record), ".dat")
  writeBin(bytes, paste0(record, ".dat"))

  units <- SummarizedExperiment::colData(x)$unit
  units <- if (is.null(units)) rep("mV", nsig) else as.character(units)
  units <- rep(units, length.out = nsig)
  units[is.na(units) | !nzchar(units)] <- "mV"
  adcres <- switch(as.character(format), "80" = 8L, "212" = 12L, "24" = 24L,
                   "32" = 32L, 16L)
  hea <- c(sprintf("%s %d %s %d", basename(record), nsig,
                   format(fs, trim = TRUE), nsamp))
  for (i in seq_len(nsig)) {
    hea <- c(hea, sprintf("%s %d %g(%d)/%s %d %d 0 0 0 %s",
                          datfile, format, gain[i], baseline[i], units[i],
                          adcres, baseline[i], labels[i]))
  }
  writeLines(hea, paste0(record, ".hea"))
  invisible(record)
}

# ---- annotations (.atr / .qrs / ...) ----------------------------------------

#' Read a WFDB annotation file
#'
#' Parses a WFDB binary annotation file (MIT format) into a
#' \code{PhysioEvents}: each annotation's sample number becomes the event
#' \code{onset} (in samples), its beat symbol the event \code{type}, and any
#' auxiliary string the event \code{value}.
#'
#' @param path Path to the annotation file (e.g. \code{"100.atr"}).
#' @return A \code{PhysioEvents} object (onset in samples).
#' @seealso \code{\link{writeWFDBAnnotation}}
#' @export
readWFDBAnnotation <- function(path) {
  raw <- readBin(path, "raw", file.info(path)$size)
  w <- readBin(raw, "integer", length(raw) %/% 2L, size = 2L,
               signed = FALSE, endian = "little")
  samples <- numeric(0); symbols <- character(0); auxs <- character(0)
  t <- 0; i <- 1L; nw <- length(w)            # t is a double (sample index)
  cur_sym <- NA_character_; cur_aux <- ""
  flush <- function() {
    if (!is.na(cur_sym)) {
      samples[[length(samples) + 1L]] <<- t
      symbols[[length(symbols) + 1L]] <<- cur_sym
      auxs[[length(auxs) + 1L]] <<- cur_aux
    }
  }
  while (i <= nw) {
    A <- w[i]; i <- i + 1L
    code <- bitwShiftR(A, 10); interval <- bitwAnd(A, 1023L)
    if (code == 0L && interval == 0L) break            # end of file
    if (code == 59L) {                                 # SKIP: 32-bit interval
      flush(); cur_sym <- NA_character_                # emit pending at its time
      hi <- w[i]; lo <- w[i + 1L]; i <- i + 2L
      t <- t + hi * 65536 + lo                         # double: avoids int32 overflow
      next                                             # next word is the annotation
    }
    if (code == 63L) {                                 # AUX (modifies current)
      nb <- interval
      aux_start <- (i - 1L) * 2L + 1L
      aux_raw <- raw[aux_start:(aux_start + nb - 1L)]
      cur_aux <- rawToChar(aux_raw[aux_raw != as.raw(0)])
      i <- i + (nb + 1L) %/% 2L
      next
    }
    if (code %in% c(60L, 61L, 62L)) next               # NUM/SUB/CHN modifiers
    flush()                                            # a real annotation
    t <- t + interval
    cur_sym <- .wfdb_symbol(code); cur_aux <- ""
  }
  flush()
  PhysioEvents(onset = as.numeric(samples), duration = 0,
               type = symbols, value = auxs)
}

#' Write a WFDB annotation file
#'
#' Writes a \code{PhysioEvents} object (onset in samples, \code{type} = beat
#' symbol, \code{value} = auxiliary string) to a WFDB binary annotation file.
#'
#' @param events A \code{PhysioEvents} object with onsets in samples.
#' @param path Output annotation file path.
#' @return \code{path}, invisibly.
#' @seealso \code{\link{readWFDBAnnotation}}
#' @export
writeWFDBAnnotation <- function(events, path) {
  stopifnot(methods::is(events, "PhysioEvents"))
  df <- as.data.frame(events@events)
  ord <- order(df$onset)
  samples <- round(df$onset[ord])                      # doubles: no int32 overflow
  symbols <- as.character(df$type[ord])
  auxs <- as.character(df$value[ord])
  codes <- .wfdb_code(symbols)

  con <- file(path, "wb"); on.exit(close(con))
  prev <- 0
  for (k in seq_along(samples)) {
    interval <- samples[k] - prev
    prev <- samples[k]
    if (interval > 1023 || interval < 0) {             # SKIP for large gaps
      writeBin(as.integer(bitwShiftL(59L, 10)), con, size = 2L, endian = "little")
      writeBin(as.integer(interval %/% 65536), con, size = 2L, endian = "little")
      writeBin(as.integer(interval %% 65536), con, size = 2L, endian = "little")
      interval <- 0
    }
    A <- bitwOr(bitwShiftL(codes[k], 10), as.integer(interval) %% 1024L)
    writeBin(as.integer(A), con, size = 2L, endian = "little")
    if (nzchar(auxs[k])) {                              # AUX record
      ab <- charToRaw(auxs[k]); nb <- length(ab)
      if (nb > 1023L) stop("WFDB AUX string exceeds 1023 bytes", call. = FALSE)
      writeBin(as.integer(bitwOr(bitwShiftL(63L, 10), nb)), con,
               size = 2L, endian = "little")
      writeBin(ab, con)
      if (nb %% 2L == 1L) writeBin(as.raw(0), con)      # pad to even
    }
  }
  writeBin(0L, con, size = 2L, endian = "little")       # end-of-file marker
  invisible(path)
}

# ---- PhysioNet helpers ------------------------------------------------------

#' List the records in a WFDB RECORDS file
#'
#' @param path Path (or URL) to a PhysioNet \code{RECORDS} file: one record
#'   name per line.
#' @return Character vector of record names.
#' @export
listWFDBRecords <- function(path) {
  x <- readLines(path, warn = FALSE)
  x <- trimws(x)
  x[nzchar(x) & !grepl("^#", x)]
}

#' Download a WFDB record from PhysioNet
#'
#' Downloads the \code{.hea}, \code{.dat} and (optionally) annotation files of a
#' record from a PhysioNet database into \code{dest}.
#'
#' @param record Record name (e.g. \code{"100"}).
#' @param database PhysioNet database slug (e.g. \code{"mitdb"}).
#' @param dest Destination directory (created if needed).
#' @param annotator Optional annotation extension(s) to fetch (e.g.
#'   \code{"atr"}).
#' @param base_url PhysioNet base URL.
#' @return The paths of the downloaded files, invisibly.
#' @export
downloadPhysioNet <- function(record, database, dest = ".", annotator = "atr",
                              base_url = "https://physionet.org/files") {
  if (!dir.exists(dest)) dir.create(dest, recursive = TRUE)
  exts <- c("hea", "dat", annotator)
  paths <- character(0)
  for (ext in exts) {
    url <- sprintf("%s/%s/1.0.0/%s.%s", base_url, database, record, ext)
    out <- file.path(dest, paste0(record, ".", ext))
    ok <- tryCatch({
      utils::download.file(url, out, mode = "wb", quiet = TRUE); TRUE
    }, error = function(e) FALSE)
    if (ok) paths <- c(paths, out)
  }
  invisible(paths)
}
