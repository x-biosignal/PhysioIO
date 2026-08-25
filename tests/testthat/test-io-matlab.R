# Tests for MATLAB .mat file I/O

# Skip all tests if R.matlab not available
skip_if_no_rmatlab <- function() {
  skip_if_not_installed("R.matlab")
}

test_that("writeMAT exports data correctly", {
  skip_if_no_rmatlab()

  pe <- PhysioExperiment(
    assays = list(raw = matrix(1:20, nrow = 10, ncol = 2)),
    colData = S4Vectors::DataFrame(label = c("Ch1", "Ch2")),
    samplingRate = 100
  )

  tmp <- tempfile(fileext = ".mat")
  on.exit(unlink(tmp))

  writeMAT(pe, tmp)

  expect_true(file.exists(tmp))

  # Read back and verify structure
  mat <- R.matlab::readMat(tmp)
  expect_true("data" %in% names(mat))
  expect_true("srate" %in% names(mat))
  expect_true("channels" %in% names(mat))
})

test_that("writeMAT uses custom variable name", {
  skip_if_no_rmatlab()

  pe <- PhysioExperiment(
    assays = list(raw = matrix(1:20, nrow = 10, ncol = 2)),
    samplingRate = 100
  )

  tmp <- tempfile(fileext = ".mat")
  on.exit(unlink(tmp))

  writeMAT(pe, tmp, data_var = "EEGdata")

  mat <- R.matlab::readMat(tmp)
  expect_true("EEGdata" %in% names(mat))
  expect_false("data" %in% names(mat))
})

test_that("readMAT reads basic .mat file", {
  skip_if_no_rmatlab()

  # Create a test .mat file
  tmp <- tempfile(fileext = ".mat")
  on.exit(unlink(tmp))

  test_data <- matrix(rnorm(100), nrow = 10, ncol = 10)
  R.matlab::writeMat(tmp, data = test_data, srate = 256)

  pe <- readMAT(tmp)

  expect_s4_class(pe, "PhysioExperiment")
  expect_equal(samplingRate(pe), 256)
})

test_that("readMAT auto-detects data variable", {
  skip_if_no_rmatlab()

  tmp <- tempfile(fileext = ".mat")
  on.exit(unlink(tmp))

  # Try different common variable names
  R.matlab::writeMat(tmp, signal = matrix(rnorm(50), nrow = 10, ncol = 5), fs = 100)

  pe <- readMAT(tmp, data_var = "signal", sr_var = "fs")

  expect_s4_class(pe, "PhysioExperiment")
  expect_equal(samplingRate(pe), 100)
})

test_that("readMAT handles transpose", {
  skip_if_no_rmatlab()

  tmp <- tempfile(fileext = ".mat")
  on.exit(unlink(tmp))

  # Create MATLAB-style data (channels x samples)
  R.matlab::writeMat(tmp, data = matrix(1:100, nrow = 10, ncol = 100), srate = 256)

  pe <- readMAT(tmp, transpose = TRUE)

  # Should have 100 samples (rows) and 10 channels (cols)
  dims <- dim(SummarizedExperiment::assay(pe))
  expect_equal(dims[1], 100)
  expect_equal(dims[2], 10)
})

test_that("MAT round-trip preserves data", {
  skip_if_no_rmatlab()

  set.seed(123)
  original <- PhysioExperiment(
    assays = list(raw = matrix(rnorm(100), nrow = 50, ncol = 2)),
    colData = S4Vectors::DataFrame(label = c("Ch1", "Ch2")),
    samplingRate = 256
  )

  tmp <- tempfile(fileext = ".mat")
  on.exit(unlink(tmp))

  writeMAT(original, tmp)
  restored <- readMAT(tmp)

  orig_data <- SummarizedExperiment::assay(original)
  rest_data <- SummarizedExperiment::assay(restored)

  # readMAT auto-transposes when ncol >> nrow, so data should match directly
  expect_equal(dim(orig_data), dim(rest_data))
  expect_true(all(abs(orig_data - rest_data) < 1e-10))
})

test_that("readMAT errors on non-existent file", {
  skip_if_no_rmatlab()

  expect_error(readMAT("nonexistent.mat"), "not found")
})

test_that("readMAT errors when data variable not found", {
  skip_if_no_rmatlab()

  tmp <- tempfile(fileext = ".mat")
  on.exit(unlink(tmp))

  R.matlab::writeMat(tmp, other_var = c(1, 2, 3))

  expect_error(readMAT(tmp, data_var = "nonexistent"), "not find")
})

test_that("writeMAT exports events when present", {
  skip_if_no_rmatlab()

  pe <- PhysioExperiment(
    assays = list(raw = matrix(rnorm(100), nrow = 50, ncol = 2)),
    samplingRate = 100
  )
  pe <- setEvents(pe, PhysioEvents(
    onset = c(1.0, 2.0),
    duration = c(0.1, 0.1),
    type = c("stim", "stim")
  ))

  tmp <- tempfile(fileext = ".mat")
  on.exit(unlink(tmp))

  writeMAT(pe, tmp)

  mat <- R.matlab::readMat(tmp)
  # R.matlab converts underscores to dots in variable names
  expect_true("event.onset" %in% names(mat))
  expect_true("event.type" %in% names(mat))
})

test_that("writeMAT without metadata", {
  skip_if_no_rmatlab()

  pe <- PhysioExperiment(
    assays = list(raw = matrix(1:20, nrow = 10, ncol = 2)),
    samplingRate = 100
  )

  tmp <- tempfile(fileext = ".mat")
  on.exit(unlink(tmp))

  writeMAT(pe, tmp, include_metadata = FALSE)

  mat <- R.matlab::readMat(tmp)
  expect_true("data" %in% names(mat))
  expect_false("srate" %in% names(mat))
  expect_false("channels" %in% names(mat))
})

test_that("writeMAT errors on invalid object", {
  skip_if_no_rmatlab()

  expect_error(writeMAT(list(), "test.mat"), "PhysioExperiment")
})
