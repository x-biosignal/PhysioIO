library(testthat)
library(PhysioIO)

reticulate_mne_available <- function() {
  requireNamespace("reticulate", quietly = TRUE) &&
    isTRUE(tryCatch(reticulate::py_module_available("mne"), error = function(e) FALSE))
}

# ---- helpers to craft a minimal big-endian FIFF tag stream ------------------

.i32 <- function(v) writeBin(as.integer(v), raw(), size = 4L, endian = "big")
.f32 <- function(v) writeBin(as.double(v), raw(), size = 4L, endian = "big")

.fif_tag <- function(kind, type, data_raw, nxt = 0L) {
  c(.i32(kind), .i32(type), .i32(length(data_raw)), .i32(nxt), data_raw)
}

.mk_ch_info <- function(kind, range, cal, unit, unit_mul, name) {
  nm <- raw(16); b <- charToRaw(substr(name, 1, 15)); nm[seq_along(b)] <- b
  c(.i32(0), .i32(0), .i32(kind), .f32(range), .f32(cal), .i32(0),  # 24 bytes
    raw(48),                                                        # loc (12 floats)
    .i32(unit), .i32(unit_mul),                                     # 8 bytes
    nm)                                                             # 16 bytes -> 96
}

# Same layout, but the 16-byte name field is supplied as explicit raw bytes so a
# test can inject Latin-1 / post-NUL padding that .mk_ch_info's ASCII path can't.
.mk_ch_info_raw <- function(kind, unit, name16) {
  stopifnot(length(name16) == 16L)
  c(.i32(0), .i32(0), .i32(kind), .f32(1), .f32(1), .i32(0),
    raw(48), .i32(unit), .i32(0L), name16)
}

# Decode raw bytes the way a correct FIFF reader should (Latin-1 -> UTF-8).
.latin1_to_utf8 <- function(bytes) {
  s <- rawToChar(as.raw(bytes)); Encoding(s) <- "latin1"; enc2utf8(s)
}

# raw_data: nsamp x nchan matrix of digital values; chs: list of ch-info specs
.craft_fif <- function(path, sfreq, chs, raw_data) {
  nchan <- length(chs)
  stopifnot(ncol(raw_data) == nchan)
  # data buffer is sample-major (channels vary fastest)
  buf <- .f32(as.vector(t(raw_data)))
  bytes <- c(
    .fif_tag(100L, 31L, raw(20)),                 # FILE_ID (contents unused here)
    .fif_tag(200L, 3L, .i32(nchan)),              # NCHAN
    .fif_tag(201L, 4L, .f32(sfreq)),              # SFREQ
    .fif_tag(208L, 3L, .i32(0L)))                 # FIRST_SAMPLE
  for (c in chs) {
    bytes <- c(bytes, .fif_tag(203L, 30L,
      .mk_ch_info(c$kind, c$range, c$cal, c$unit, c$unit_mul, c$name)))
  }
  bytes <- c(bytes, .fif_tag(300L, 4L, buf))      # DATA_BUFFER (float32)
  writeBin(bytes, path)
  invisible(path)
}

test_that("native FIFF parser reads a crafted tag directory correctly", {
  chs <- list(
    list(kind = 2L, range = 1, cal = 1e-6, unit = 107L, unit_mul = 0L, name = "EEG 001"),
    list(kind = 3L, range = 1, cal = 1, unit = -1L, unit_mul = 0L, name = "STI 014"))
  raw_data <- matrix(c(1, 2, 3, 4,      # EEG (col 1)
                       10, 20, 30, 40), # STIM (col 2)
                     nrow = 4, ncol = 2)
  f <- tempfile(fileext = ".fif")
  .craft_fif(f, sfreq = 250, chs = chs, raw_data = raw_data)

  x <- readFIF(f, backend = "native")
  unlink(f)
  expect_s4_class(x, "PhysioExperiment")
  expect_equal(samplingRate(x), 250)
  expect_equal(channelNames(x), c("EEG 001", "STI 014"))
  expect_equal(ncol(SummarizedExperiment::assay(x, "raw")), 2L)
  expect_equal(nrow(SummarizedExperiment::assay(x, "raw")), 4L)

  # physical = digital * range * cal
  d <- SummarizedExperiment::assay(x, "raw")
  expect_equal(d[, 1], c(1, 2, 3, 4) * 1e-6)      # EEG, cal 1e-6
  expect_equal(d[, 2], c(10, 20, 30, 40))         # STIM, cal 1

  cd <- SummarizedExperiment::colData(x)
  expect_equal(as.character(cd$type), c("eeg", "stim"))
  expect_equal(as.character(cd$unit), c("V", "none"))
})

test_that("native FIFF parser handles an integer (short) data buffer", {
  # override the buffer type to FIFFT_SHORT (int16)
  chs <- list(list(kind = 2L, range = 1, cal = 2, unit = 107L, unit_mul = 0L,
                   name = "EEG 001"))
  f <- tempfile(fileext = ".fif")
  bytes <- c(
    .fif_tag(100L, 31L, raw(20)),
    .fif_tag(200L, 3L, .i32(1L)),
    .fif_tag(201L, 4L, .f32(500)),
    .fif_tag(203L, 30L, .mk_ch_info(2L, 1, 2, 107L, 0L, "EEG 001")),
    .fif_tag(300L, 2L, writeBin(c(100L, -100L, 32000L), raw(),
                                size = 2L, endian = "big")))
  writeBin(bytes, f)
  x <- readFIF(f, backend = "native"); unlink(f)
  expect_equal(SummarizedExperiment::assay(x, "raw")[, 1], c(100, -100, 32000) * 2)
  expect_equal(samplingRate(x), 500)
})

test_that("readFIF rejects a non-FIFF file", {
  f <- tempfile(fileext = ".fif")
  writeBin(as.raw(rep(0, 64)), f)                 # no FILE_ID (kind 0)
  expect_error(readFIF(f, backend = "native"), "FIFF")
  unlink(f)
})

test_that("readFIF errors clearly when the mne fallback is unavailable", {
  skip_if(reticulate_mne_available())
  f <- tempfile(fileext = ".fif")
  writeBin(as.raw(rep(0, 32)), f)
  expect_error(readFIF(f, backend = "mne"), "mne")
  unlink(f)
})

# ---- regression tests for adversarial-review findings ----------------------

test_that("channel kinds ref_meg (301) and mcg (201) map correctly", {
  chs <- list(
    list(kind = 301L, range = 1, cal = 1, unit = 112L, unit_mul = 0L, name = "MEG 001"),
    list(kind = 201L, range = 1, cal = 1, unit = 112L, unit_mul = 0L, name = "MCG 001"))
  f <- tempfile(fileext = ".fif")
  .craft_fif(f, sfreq = 600, chs = chs, raw_data = matrix(1:4, 2, 2))
  x <- readFIF(f, backend = "native"); unlink(f)
  expect_equal(as.character(SummarizedExperiment::colData(x)$type),
               c("ref_meg", "mcg"))
})

test_that("a data buffer not aligned to nchan is rejected (no silent shear)", {
  f <- tempfile(fileext = ".fif")
  bytes <- c(
    .fif_tag(100L, 31L, raw(20)),
    .fif_tag(200L, 3L, .i32(2L)),                 # nchan = 2
    .fif_tag(201L, 4L, .f32(250)),
    .fif_tag(203L, 30L, .mk_ch_info(2L, 1, 1, 107L, 0L, "A")),
    .fif_tag(203L, 30L, .mk_ch_info(2L, 1, 1, 107L, 0L, "B")),
    .fif_tag(300L, 4L, .f32(c(1, 2, 3))))         # 3 floats, not a multiple of 2
  writeBin(bytes, f)
  expect_error(readFIF(f, backend = "native"), "multiple of nchan")
  unlink(f)
})

test_that("a FIFF without SFREQ is rejected", {
  f <- tempfile(fileext = ".fif")
  bytes <- c(
    .fif_tag(100L, 31L, raw(20)),
    .fif_tag(200L, 3L, .i32(1L)),
    .fif_tag(203L, 30L, .mk_ch_info(2L, 1, 1, 107L, 0L, "A")),
    .fif_tag(300L, 4L, .f32(c(1, 2))))            # no SFREQ tag
  writeBin(bytes, f)
  expect_error(readFIF(f, backend = "native"), "SFREQ")
  unlink(f)
})

test_that("auto backend surfaces the native error when mne is unavailable", {
  skip_if(reticulate_mne_available())
  f <- tempfile(fileext = ".fif")
  bytes <- c(.fif_tag(100L, 31L, raw(20)),        # valid FILE_ID but no NCHAN
             .fif_tag(201L, 4L, .f32(250)))
  writeBin(bytes, f)
  expect_error(readFIF(f, backend = "auto"), "native FIFF read failed")
  unlink(f)
})

test_that("native parser decodes a Latin-1 channel name without erroring", {
  # DMIO-18: real FIFF files carry Latin-1 (not UTF-8) strings. "EEGé1"
  # with the raw Latin-1 byte 0xE9 must decode, not abort trimws() with an
  # "invalid UTF-8" error.
  name16 <- raw(16)
  name16[1:5] <- as.raw(c(0x45, 0x45, 0x47, 0xE9, 0x31))   # E E G <e9> 1
  f <- tempfile(fileext = ".fif")
  bytes <- c(
    .fif_tag(100L, 31L, raw(20)),
    .fif_tag(200L, 3L, .i32(1L)),
    .fif_tag(201L, 4L, .f32(250)),
    .fif_tag(203L, 30L, .mk_ch_info_raw(2L, 107L, name16)),
    .fif_tag(300L, 4L, .f32(c(1, 2, 3))))
  writeBin(bytes, f)
  x <- readFIF(f, backend = "native"); unlink(f)
  expect_equal(channelNames(x), .latin1_to_utf8(c(0x45, 0x45, 0x47, 0xE9, 0x31)))
  expect_true(validUTF8(channelNames(x)))
})

test_that("native parser stops at the NUL and ignores post-terminator bytes", {
  # "EEG 001" then a NUL then non-UTF-8 padding: the padding must be dropped,
  # not appended (which would also make the string invalid UTF-8).
  name16 <- raw(16)
  nm <- c(charToRaw("EEG 001"), as.raw(0x00), as.raw(c(0xFF, 0xC0, 0x01)))
  name16[seq_along(nm)] <- nm
  f <- tempfile(fileext = ".fif")
  bytes <- c(
    .fif_tag(100L, 31L, raw(20)),
    .fif_tag(200L, 3L, .i32(1L)),
    .fif_tag(201L, 4L, .f32(250)),
    .fif_tag(203L, 30L, .mk_ch_info_raw(2L, 107L, name16)),
    .fif_tag(300L, 4L, .f32(c(1, 2, 3))))
  writeBin(bytes, f)
  x <- readFIF(f, backend = "native"); unlink(f)
  expect_equal(channelNames(x), "EEG 001")
  expect_true(validUTF8(channelNames(x)))
})

test_that("native parser matches MNE on a bundled MNE-written FIF", {
  # DMIO-18: parity against a genuine MNE byte layout without needing mne at
  # test time. The .fif was written by MNE; the .rds holds MNE's own read-back.
  fif <- system.file("extdata", "mne_raw_reference.fif", package = "PhysioIO")
  rds <- system.file("extdata", "mne_raw_reference.rds", package = "PhysioIO")
  skip_if(fif == "" || rds == "", "MNE parity fixture not bundled")
  ref <- readRDS(rds)

  x <- readFIF(fif, backend = "native")
  expect_equal(channelNames(x), ref$ch_names)
  expect_true(all(validUTF8(channelNames(x))))
  expect_equal(samplingRate(x), ref$sfreq)
  got <- SummarizedExperiment::assay(x, "raw")
  dimnames(got) <- NULL
  expect_equal(dim(got), dim(ref$data))
  expect_equal(got, `dimnames<-`(ref$data, NULL), tolerance = 1e-6)
})

test_that("readFIF matches mne on the MNE sample fif", {
  skip_if_not(reticulate_mne_available(), "Python 'mne' not available")
  mne <- reticulate::import("mne")
  sample_path <- tryCatch(
    file.path(mne$datasets$sample$data_path(),
              "MEG", "sample", "sample_audvis_raw.fif"),
    error = function(e) "")
  skip_if(sample_path == "" || !file.exists(sample_path), "MNE sample fif absent")

  ref <- mne$io$read_raw_fif(sample_path, preload = TRUE, verbose = FALSE)
  x <- readFIF(sample_path, backend = "native")
  expect_equal(nrow(SummarizedExperiment::colData(x)),
               as.integer(reticulate::py_to_r(ref$info$`__getitem__`("nchan"))))
  expect_equal(samplingRate(x),
               as.numeric(reticulate::py_to_r(ref$info$`__getitem__`("sfreq"))))
  ref_data <- t(reticulate::py_to_r(ref$get_data()))
  got <- SummarizedExperiment::assay(x, "raw")
  expect_equal(got[1, ], ref_data[1, ], tolerance = 1e-6)
})
