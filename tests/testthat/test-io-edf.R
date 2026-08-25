library(testthat)
library(PhysioIO)

make_edf_test_pe <- function() {
  set.seed(42)
  data <- matrix(rnorm(256 * 4 * 3), nrow = 256 * 4, ncol = 3)

  PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = data),
    colData = S4Vectors::DataFrame(
      label = c("Fp1", "Fp2", "Cz"),
      type = c("EEG", "EEG", "EEG")
    ),
    samplingRate = 256
  )
}

write_custom_mixed_rate_edf <- function(path) {
  pad <- function(x, n) {
    x <- substr(as.character(x), 1, n)
    paste0(x, paste(rep(" ", n - nchar(x)), collapse = ""))
  }

  n_channels <- 2L
  n_records <- 2L
  record_duration <- 1
  samples_per_record <- c(256L, 128L)
  labels <- c("Ch256", "Ch128")

  # Digital-domain signals. Using full EDF digital range avoids extra scaling ambiguity.
  sig1 <- as.integer(round(1000 * sin(seq(0, 4 * pi, length.out = n_records * samples_per_record[1]))))
  sig2 <- as.integer(round(500 * cos(seq(0, 2 * pi, length.out = n_records * samples_per_record[2]))))

  con <- file(path, "wb")
  on.exit(close(con), add = TRUE)

  # Main header (256 bytes)
  writeBin(charToRaw(pad("0", 8)), con)
  writeBin(charToRaw(pad("X", 80)), con)
  writeBin(charToRaw(pad("MixedRate", 80)), con)
  writeBin(charToRaw(pad("01.01.26", 8)), con)
  writeBin(charToRaw(pad("00.00.00", 8)), con)
  writeBin(charToRaw(pad(as.character(256 + n_channels * 256), 8)), con)
  writeBin(charToRaw(pad("", 44)), con)
  writeBin(charToRaw(pad(as.character(n_records), 8)), con)
  writeBin(charToRaw(pad(as.character(record_duration), 8)), con)
  writeBin(charToRaw(pad(as.character(n_channels), 4)), con)

  # Signal headers
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad(labels[i], 16)), con)
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("", 80)), con)
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("uV", 8)), con)
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("-32768", 8)), con)
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("32767", 8)), con)
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("-32768", 8)), con)
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("32767", 8)), con)
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("", 80)), con)
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad(as.character(samples_per_record[i]), 8)), con)
  for (i in seq_len(n_channels)) writeBin(charToRaw(pad("", 32)), con)

  # Data records, channel-major within each record.
  for (rec in seq_len(n_records)) {
    s1 <- (rec - 1) * samples_per_record[1] + 1
    e1 <- rec * samples_per_record[1]
    writeBin(sig1[s1:e1], con, size = 2L, endian = "little")

    s2 <- (rec - 1) * samples_per_record[2] + 1
    e2 <- rec * samples_per_record[2]
    writeBin(sig2[s2:e2], con, size = 2L, endian = "little")
  }
}

test_that("writeEDF/readEDF preserves structure", {
  pe <- make_edf_test_pe()
  tmp <- tempfile(fileext = ".edf")
  on.exit(unlink(tmp), add = TRUE)

  writeEDF(pe, tmp, patient_id = "S01", recording_id = "R01")
  expect_true(file.exists(tmp))

  loaded <- readEDF(tmp)
  expect_s4_class(loaded, "PhysioExperiment")
  expect_equal(samplingRate(loaded), 256)
  expect_equal(dim(SummarizedExperiment::assay(loaded)), c(1024, 3))
  expect_equal(channelNames(loaded), c("Fp1", "Fp2", "Cz"))
  expect_true("time_idx" %in% names(SummarizedExperiment::rowData(loaded)))
  expect_equal(nrow(SummarizedExperiment::rowData(loaded)), 1024)
})

test_that("readEDF supports channel selection", {
  pe <- make_edf_test_pe()
  tmp <- tempfile(fileext = ".edf")
  on.exit(unlink(tmp), add = TRUE)
  writeEDF(pe, tmp)

  loaded <- readEDF(tmp, channels = c("Fp1", "Cz"))
  expect_equal(dim(SummarizedExperiment::assay(loaded)), c(1024, 2))
  expect_equal(channelNames(loaded), c("Fp1", "Cz"))
})

test_that("readEDF supports time window selection", {
  pe <- make_edf_test_pe()
  tmp <- tempfile(fileext = ".edf")
  on.exit(unlink(tmp), add = TRUE)
  writeEDF(pe, tmp)

  loaded <- readEDF(tmp, start_time = 1, end_time = 3)
  expect_equal(dim(SummarizedExperiment::assay(loaded)), c(512, 3))
  expect_equal(samplingRate(loaded), 256)
})

test_that("writeEDF accepts 3D array with singleton 3rd dimension", {
  arr <- array(rnorm(100 * 2), dim = c(100, 2, 1))
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = arr),
    colData = S4Vectors::DataFrame(label = c("C1", "C2")),
    samplingRate = 100
  )

  tmp <- tempfile(fileext = ".edf")
  on.exit(unlink(tmp), add = TRUE)

  expect_no_error(writeEDF(pe, tmp))
  loaded <- readEDF(tmp)
  expect_equal(dim(SummarizedExperiment::assay(loaded)), c(100, 2))
})

test_that("readEDF errors for invalid inputs", {
  expect_error(readEDF("nonexistent.edf"), "not found")

  pe <- make_edf_test_pe()
  tmp <- tempfile(fileext = ".edf")
  on.exit(unlink(tmp), add = TRUE)
  writeEDF(pe, tmp)

  expect_error(readEDF(tmp, channels = c("Missing")), "Channels not found")
  expect_error(readEDF(tmp, start_time = 10), "exceeds recording duration")
  expect_error(readEDF(tmp, start_time = 2, end_time = 1), "Invalid end_time")
})

test_that("readEDF preserves native rates when sampling rates differ", {
  tmp <- tempfile(fileext = ".edf")
  on.exit(unlink(tmp), add = TRUE)
  write_custom_mixed_rate_edf(tmp)

  # DMIO-05: differing native rates are preserved (no silent resample)
  loaded <- readEDF(tmp)
  expect_s4_class(loaded, "MultiRatePhysioExperiment")
  expect_equal(unname(sort(streamRates(loaded))), c(128, 256))

  # legacy opt-in: resample = TRUE force-resamples to the common (max) rate
  legacy <- suppressMessages(readEDF(tmp, resample = TRUE))
  data <- SummarizedExperiment::assay(legacy)
  expect_equal(samplingRate(legacy), 256)
  expect_equal(dim(data), c(512, 2))
  expect_equal(channelNames(legacy), c("Ch256", "Ch128"))
  expect_false(anyNA(data))
})
