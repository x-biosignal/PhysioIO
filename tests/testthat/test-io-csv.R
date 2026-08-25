# Tests for CSV I/O functions

test_that("writeCSV exports data in wide format", {
  pe <- PhysioExperiment(
    assays = list(raw = matrix(1:20, nrow = 10, ncol = 2)),
    colData = S4Vectors::DataFrame(label = c("Ch1", "Ch2")),
    samplingRate = 100
  )

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  writeCSV(pe, tmp, format = "wide")

  expect_true(file.exists(tmp))

  # Read back and verify
  df <- read.csv(tmp)
  expect_equal(ncol(df), 3)  # time + 2 channels
  expect_equal(nrow(df), 10)
  expect_true("time" %in% names(df))
})

test_that("writeCSV exports data in long format", {
  pe <- PhysioExperiment(
    assays = list(raw = matrix(1:20, nrow = 10, ncol = 2)),
    colData = S4Vectors::DataFrame(label = c("Ch1", "Ch2")),
    samplingRate = 100
  )

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  writeCSV(pe, tmp, format = "long")

  expect_true(file.exists(tmp))

  # Read back and verify
  df <- read.csv(tmp)
  expect_equal(nrow(df), 20)  # 10 samples * 2 channels
  expect_true(all(c("time", "channel", "value") %in% names(df)))
})

test_that("writeCSV respects custom separator", {
  pe <- PhysioExperiment(
    assays = list(raw = matrix(1:20, nrow = 10, ncol = 2)),
    colData = S4Vectors::DataFrame(label = c("Ch1", "Ch2")),
    samplingRate = 100
  )

  tmp <- tempfile(fileext = ".tsv")
  on.exit(unlink(tmp))

  writeCSV(pe, tmp, format = "wide", sep = "\t")

  df <- read.delim(tmp)
  expect_equal(ncol(df), 3)
  expect_true(all(c("time", "Ch1", "Ch2") %in% names(df)))
})

test_that("readCSV reads wide format data", {
  # Create test CSV
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  df <- data.frame(
    time = seq(0, 0.09, by = 0.01),
    Ch1 = rnorm(10),
    Ch2 = rnorm(10)
  )
  write.csv(df, tmp, row.names = FALSE)

  pe <- readCSV(tmp, format = "wide", time_col = "time",
                channel_cols = c("Ch1", "Ch2"), sampling_rate = 100)

  expect_s4_class(pe, "PhysioExperiment")
  expect_equal(nrow(SummarizedExperiment::assay(pe)), 10)
  expect_equal(ncol(SummarizedExperiment::assay(pe)), 2)
  expect_equal(samplingRate(pe), 100)
})

test_that("readCSV reads long format data", {
  # Create test CSV
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  df <- data.frame(
    time = rep(seq(0, 0.09, by = 0.01), 2),
    channel = rep(c("Ch1", "Ch2"), each = 10),
    value = rnorm(20)
  )
  write.csv(df, tmp, row.names = FALSE)

  pe <- readCSV(tmp, format = "long", time_col = "time",
                sampling_rate = 100)

  expect_s4_class(pe, "PhysioExperiment")
  expect_equal(nrow(SummarizedExperiment::assay(pe)), 10)
  expect_equal(ncol(SummarizedExperiment::assay(pe)), 2)
})

test_that("readCSV auto-detects sampling rate from time column", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  df <- data.frame(
    time = seq(0, 0.099, by = 0.001),  # 1000 Hz
    Ch1 = rnorm(100)
  )
  write.csv(df, tmp, row.names = FALSE)

  pe <- readCSV(tmp, format = "wide", time_col = "time",
                channel_cols = "Ch1")

  expect_equal(samplingRate(pe), 1000)
})

test_that("readCSV handles TSV files", {
  tmp <- tempfile(fileext = ".tsv")
  on.exit(unlink(tmp))

  df <- data.frame(
    time = seq(0, 0.09, by = 0.01),
    Ch1 = rnorm(10)
  )
  write.table(df, tmp, sep = "\t", row.names = FALSE)

  pe <- readCSV(tmp, format = "wide", time_col = "time",
                channel_cols = "Ch1", sep = "\t")

  expect_s4_class(pe, "PhysioExperiment")
})

test_that("writeEventsCSV exports events correctly", {
  events <- PhysioEvents(
    onset = c(1.0, 2.5, 4.0),
    duration = c(0.5, 0.5, 1.0),
    type = c("stim", "stim", "response"),
    value = c("A", "B", "correct")
  )

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  writeEventsCSV(events, tmp)

  expect_true(file.exists(tmp))

  df <- read.csv(tmp)
  expect_equal(nrow(df), 3)
  expect_true(all(c("onset", "duration", "type", "value") %in% names(df)))
  expect_equal(df$onset, c(1.0, 2.5, 4.0))
})

test_that("writeEventsCSV respects custom separator", {
  events <- PhysioEvents(
    onset = c(1.0, 2.5),
    duration = c(0.5, 0.5),
    type = c("stim", "response"),
    value = c("A", "correct")
  )

  tmp <- tempfile(fileext = ".tsv")
  on.exit(unlink(tmp))

  writeEventsCSV(events, tmp, sep = "\t")

  df <- read.delim(tmp)
  expect_equal(nrow(df), 2)
  expect_true(all(c("onset", "duration", "type", "value") %in% names(df)))
})

test_that("readEventsCSV reads events correctly", {
  # Create test CSV
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  df <- data.frame(
    onset = c(1.0, 2.5, 4.0),
    duration = c(0.5, 0.5, 1.0),
    type = c("stim", "stim", "response"),
    value = c("A", "B", "correct")
  )
  write.csv(df, tmp, row.names = FALSE)

  events <- readEventsCSV(tmp)

  expect_s4_class(events, "PhysioEvents")
  expect_equal(nEvents(events), 3)
})

test_that("readEventsCSV handles custom column names", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  df <- data.frame(
    time_start = c(1.0, 2.5),
    length = c(0.5, 0.5),
    event_type = c("stim", "response")
  )
  write.csv(df, tmp, row.names = FALSE)

  events <- readEventsCSV(tmp, onset_col = "time_start",
                          duration_col = "length", type_col = "event_type")

  expect_s4_class(events, "PhysioEvents")
  expect_equal(nEvents(events), 2)
})

test_that("writeElectrodePositionsCSV exports positions correctly", {
  pe <- PhysioExperiment(
    assays = list(raw = matrix(rnorm(100), nrow = 50, ncol = 2)),
    colData = S4Vectors::DataFrame(label = c("Fz", "Cz")),
    samplingRate = 100
  )
  pe <- applyMontage(pe, "10-20")

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  writeElectrodePositionsCSV(pe, tmp)

  expect_true(file.exists(tmp))

  df <- read.csv(tmp)
  expect_true(all(c("channel", "x", "y") %in% names(df)))
})

test_that("writeElectrodePositionsCSV respects custom separator", {
  pe <- PhysioExperiment(
    assays = list(raw = matrix(rnorm(100), nrow = 50, ncol = 2)),
    colData = S4Vectors::DataFrame(label = c("Fz", "Cz")),
    samplingRate = 100
  )
  pe <- applyMontage(pe, "10-20")

  tmp <- tempfile(fileext = ".tsv")
  on.exit(unlink(tmp))

  writeElectrodePositionsCSV(pe, tmp, sep = "\t")

  df <- read.delim(tmp)
  expect_true(all(c("channel", "x", "y") %in% names(df)))
})

test_that("readElectrodePositionsCSV reads positions correctly", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  df <- data.frame(
    name = c("Fz", "Cz", "Pz"),
    x = c(0, 0, 0),
    y = c(0.5, 0, -0.5),
    z = c(0, 0.5, 0)
  )
  write.csv(df, tmp, row.names = FALSE)

  positions <- readElectrodePositionsCSV(tmp)

  expect_s3_class(positions, "data.frame")
  expect_equal(nrow(positions), 3)
  expect_true(all(c("name", "x", "y") %in% names(positions)))
})

test_that("CSV round-trip preserves data", {
  set.seed(123)
  original <- PhysioExperiment(
    assays = list(raw = matrix(rnorm(100), nrow = 50, ncol = 2)),
    colData = S4Vectors::DataFrame(label = c("Ch1", "Ch2")),
    samplingRate = 250
  )

  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  writeCSV(original, tmp, format = "wide")
  restored <- readCSV(tmp, format = "wide", time_col = "time",
                      channel_cols = c("Ch1", "Ch2"))

  orig_data <- SummarizedExperiment::assay(original)
  rest_data <- SummarizedExperiment::assay(restored)

  # Values should be approximately equal (CSV has limited precision)
  expect_true(all(abs(orig_data - rest_data) < 1e-6))
})

test_that("readCSV errors on non-existent file", {
  expect_error(readCSV("nonexistent.csv"), "not found")
})

test_that("writeCSV errors on invalid object", {
  expect_error(writeCSV(list(), "test.csv"), "PhysioExperiment")
})
