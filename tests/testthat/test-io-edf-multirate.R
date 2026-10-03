library(testthat)
library(PhysioIO)

# Write a minimal but valid multi-rate EDF: signal 1 "EEG" at 256 samples/record
# and signal 2 "Marker" at 1 sample/record, with a 1 s record duration -> 256 Hz
# and 1 Hz native rates.
.write_multirate_edf <- function(path, n_records = 4L) {
  con <- file(path, "wb")
  on.exit(close(con))
  padw <- function(s, n) {
    s <- as.character(s)
    if (nchar(s) > n) s <- substr(s, 1, n)
    writeBin(charToRaw(paste0(s, strrep(" ", n - nchar(s)))), con)
  }
  ns <- 2L
  spr <- c(256L, 1L)
  labels <- c("EEG", "Marker")

  padw("0", 8)                       # version (EDF)
  padw("synthetic", 80)              # patient_id
  padw("multirate", 80)              # recording_id
  padw("01.01.00", 8)                # start_date
  padw("00.00.00", 8)                # start_time
  padw(256 + ns * 256, 8)            # header bytes
  padw("", 44)                       # reserved
  padw(n_records, 8)                 # number of data records
  padw("1", 8)                       # data record duration (s)
  padw(ns, 4)                        # number of signals

  for (i in 1:ns) padw(labels[i], 16)   # labels
  for (i in 1:ns) padw("", 80)          # transducer
  for (i in 1:ns) padw("uV", 8)         # physical dimension
  for (i in 1:ns) padw("-100", 8)       # physical min
  for (i in 1:ns) padw("100", 8)        # physical max
  for (i in 1:ns) padw("-32768", 8)     # digital min
  for (i in 1:ns) padw("32767", 8)      # digital max
  for (i in 1:ns) padw("", 80)          # prefiltering
  for (i in 1:ns) padw(spr[i], 8)       # samples per record
  for (i in 1:ns) padw("", 32)          # reserved

  for (rec in seq_len(n_records)) {
    writeBin(rep(1000L, 256L), con, size = 2L)   # EEG record (256 samples)
    writeBin(as.integer(rec * 100L), con, size = 2L)  # Marker (1 sample)
  }
  invisible(path)
}

test_that("multi-rate EDF preserves both native rates (no silent resample)", {
  f <- tempfile(fileext = ".edf")
  .write_multirate_edf(f)
  x <- readEDF(f)                       # resample = FALSE (default)
  unlink(f)

  expect_s4_class(x, "MultiRatePhysioExperiment")
  # both native rates preserved, fastest stream first
  expect_equal(unname(sort(streamRates(x))), c(1, 256))
  expect_equal(nStreams(x), 2L)
  # the 256 Hz stream has 4 s * 256 = 1024 samples; the 1 Hz stream has 4
  d <- dim(x)
  expect_setequal(unname(d[, "nsamples"]), c(1024L, 4L))
})

test_that("resample = TRUE restores the legacy single-rate behaviour", {
  f <- tempfile(fileext = ".edf")
  .write_multirate_edf(f)
  x <- suppressMessages(readEDF(f, resample = TRUE))
  unlink(f)

  expect_s4_class(x, "PhysioExperiment")
  expect_equal(samplingRate(x), 256)
  # both channels present, resampled to the common (highest) rate
  expect_equal(ncol(SummarizedExperiment::assay(x, "raw")), 2L)
  expect_equal(nrow(SummarizedExperiment::assay(x, "raw")), 1024L)
})

test_that("single-rate EDF still returns a plain PhysioExperiment", {
  pe <- PhysioExperiment(
    assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
    colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "C3", "C4")),
    samplingRate = 100
  )
  f <- tempfile(fileext = ".edf")
  writeEDF(pe, f)
  back <- readEDF(f)
  unlink(f)
  expect_s4_class(back, "PhysioExperiment")
  expect_equal(samplingRate(back), 100)
})

test_that("assaySamplingRates is reachable from the PhysioCore namespace", {
  expect_true("assaySamplingRates" %in% getNamespaceExports("PhysioCore"))
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)),
    samplingRate = 100
  )
  expect_equal(unname(PhysioCore::assaySamplingRates(pe)), 100)
})
