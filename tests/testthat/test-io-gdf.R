library(testthat)
library(PhysioIO)

# --- Function existence ---

test_that("readGDF function exists", {
  expect_true(is.function(readGDF))
})

test_that("writeGDF function exists", {
  expect_true(is.function(writeGDF))
})

# --- Input validation ---

test_that("readGDF errors on non-existent file", {
  expect_error(readGDF("nonexistent_file.gdf"), "File not found")
})

test_that("writeGDF requires PhysioExperiment object", {
  expect_error(writeGDF(list(), tempfile(fileext = ".gdf")))
})

test_that("writeGDF errors when file exists and overwrite is FALSE", {
  pe <- make_pe_2d(n_time = 256, n_channels = 2, sr = 256)

  tmp <- tempfile(fileext = ".gdf")
  on.exit(unlink(tmp))

  writeGDF(pe, tmp)
  expect_error(
    writeGDF(pe, tmp, overwrite = FALSE),
    "File already exists"
  )
})

# --- GDF write functionality ---

test_that("writeGDF creates a file", {
  pe <- make_pe_2d(n_time = 256, n_channels = 3, sr = 256)

  tmp <- tempfile(fileext = ".gdf")
  on.exit(unlink(tmp))

  writeGDF(pe, tmp)
  expect_true(file.exists(tmp))
  expect_gt(file.info(tmp)$size, 0)
})

test_that("writeGDF returns invisible NULL", {
  pe <- make_pe_2d(n_time = 256, n_channels = 2, sr = 256)

  tmp <- tempfile(fileext = ".gdf")
  on.exit(unlink(tmp))

  result <- writeGDF(pe, tmp)
  expect_null(result)
})

test_that("writeGDF accepts patient_id and recording_id", {
  pe <- make_pe_2d(n_time = 256, n_channels = 2, sr = 256)

  tmp <- tempfile(fileext = ".gdf")
  on.exit(unlink(tmp))

  expect_silent(writeGDF(pe, tmp, patient_id = "Subject01", recording_id = "Run1"))
  expect_true(file.exists(tmp))
})

test_that("writeGDF with overwrite = TRUE replaces existing file", {
  pe <- make_pe_2d(n_time = 256, n_channels = 2, sr = 256)

  tmp <- tempfile(fileext = ".gdf")
  on.exit(unlink(tmp))

  writeGDF(pe, tmp)
  size1 <- file.info(tmp)$size

  pe2 <- make_pe_2d(n_time = 512, n_channels = 2, sr = 256)
  writeGDF(pe2, tmp, overwrite = TRUE)
  size2 <- file.info(tmp)$size

  # File should exist and differ in size
  expect_true(file.exists(tmp))
  expect_true(size2 > size1)
})

# --- GDF round-trip write -> read ---

test_that("GDF write-read round-trip preserves structure", {
  pe <- make_pe_2d(n_time = 256, n_channels = 3, sr = 256)

  tmp <- tempfile(fileext = ".gdf")
  on.exit(unlink(tmp))

  writeGDF(pe, tmp)
  pe_read <- readGDF(tmp)

  expect_s4_class(pe_read, "PhysioExperiment")

  read_dim <- dim(SummarizedExperiment::assay(pe_read))
  expect_equal(read_dim[2], 3)  # same number of channels
})

test_that("GDF round-trip preserves sampling rate", {
  pe <- make_pe_2d(n_time = 256, n_channels = 2, sr = 256)

  tmp <- tempfile(fileext = ".gdf")
  on.exit(unlink(tmp))

  writeGDF(pe, tmp)
  pe_read <- readGDF(tmp)

  expect_equal(samplingRate(pe_read), 256)
})

test_that("GDF round-trip preserves channel labels", {
  pe <- make_pe_2d(n_time = 256, n_channels = 3, sr = 256)

  tmp <- tempfile(fileext = ".gdf")
  on.exit(unlink(tmp))

  writeGDF(pe, tmp)
  pe_read <- readGDF(tmp)

  col_data <- SummarizedExperiment::colData(pe_read)
  expect_true("label" %in% names(col_data))
  expect_equal(nrow(col_data), 3)
})

test_that("GDF round-trip preserves data approximately", {
  set.seed(42)
  pe <- make_pe_2d(n_time = 256, n_channels = 2, sr = 256)

  tmp <- tempfile(fileext = ".gdf")
  on.exit(unlink(tmp))

  writeGDF(pe, tmp)
  pe_read <- readGDF(tmp)

  orig_data <- SummarizedExperiment::assay(pe)
  read_data <- SummarizedExperiment::assay(pe_read)

  # GDF uses int16, so there will be quantization error, but correlation
  # should be high

  n_check <- min(nrow(orig_data), nrow(read_data))
  for (ch in seq_len(ncol(orig_data))) {
    r <- cor(orig_data[seq_len(n_check), ch], read_data[seq_len(n_check), ch])
    expect_gt(r, 0.99)
  }
})

# --- GDF metadata ---

test_that("readGDF populates metadata with GDF version info", {
  pe <- make_pe_2d(n_time = 256, n_channels = 2, sr = 256)

  tmp <- tempfile(fileext = ".gdf")
  on.exit(unlink(tmp))

  writeGDF(pe, tmp)
  pe_read <- readGDF(tmp)

  meta <- S4Vectors::metadata(pe_read)
  expect_true("gdf_version" %in% names(meta))
})

# --- readGDF rejects non-GDF files ---

test_that("readGDF errors on non-GDF file", {
  pe <- make_pe_2d(n_time = 250, n_channels = 2, sr = 250)

  tmp <- tempfile(fileext = ".gdf")
  on.exit(unlink(tmp))

  # Write an EDF file (not GDF) and try to read as GDF
  writeEDF(pe, tmp)

  expect_error(readGDF(tmp), "Not a valid GDF file")
})
