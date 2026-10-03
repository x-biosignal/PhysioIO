library(testthat)
library(PhysioIO)

# --- Function existence ---

test_that("readBrainVision function exists", {
  expect_true(is.function(readBrainVision))
})

test_that("writeBrainVision function exists", {
  expect_true(is.function(writeBrainVision))
})

# --- Input validation ---

test_that("readBrainVision errors on non-existent file", {
  expect_error(readBrainVision("nonexistent.vhdr"), "File not found")
})

test_that("readBrainVision errors on non-.vhdr file", {
  tmp <- tempfile(fileext = ".txt")
  writeLines("test", tmp)
  on.exit(unlink(tmp))

  expect_error(readBrainVision(tmp), "must be a .vhdr header file")
})

test_that("writeBrainVision requires PhysioExperiment object", {
  expect_error(writeBrainVision(list(), tempfile()), "PhysioExperiment")
})

# --- BrainVision round-trip write -> read ---

test_that("BrainVision write-read round-trip preserves structure", {
  set.seed(42)
  pe <- make_pe_2d(n_time = 500, n_channels = 4, sr = 256)

  tmp_base <- tempfile()
  on.exit({
    unlink(paste0(tmp_base, ".vhdr"))
    unlink(paste0(tmp_base, ".vmrk"))
    unlink(paste0(tmp_base, ".eeg"))
  })

  writeBrainVision(pe, tmp_base)

  # All three files should be created
  expect_true(file.exists(paste0(tmp_base, ".vhdr")))
  expect_true(file.exists(paste0(tmp_base, ".vmrk")))
  expect_true(file.exists(paste0(tmp_base, ".eeg")))

  pe_read <- readBrainVision(paste0(tmp_base, ".vhdr"))
  expect_s4_class(pe_read, "PhysioExperiment")
  expect_equal(samplingRate(pe_read), 256)
  expect_equal(ncol(SummarizedExperiment::assay(pe_read)), 4)
})

test_that("BrainVision round-trip preserves data approximately", {
  set.seed(42)
  pe <- make_pe_2d(n_time = 256, n_channels = 2, sr = 256)

  tmp_base <- tempfile()
  on.exit({
    unlink(paste0(tmp_base, ".vhdr"))
    unlink(paste0(tmp_base, ".vmrk"))
    unlink(paste0(tmp_base, ".eeg"))
  })

  # Use float32 for best precision
  writeBrainVision(pe, tmp_base, binary_format = "IEEE_FLOAT_32")
  pe_read <- readBrainVision(paste0(tmp_base, ".vhdr"))

  orig_data <- SummarizedExperiment::assay(pe)
  read_data <- SummarizedExperiment::assay(pe_read)

  expect_equal(dim(orig_data), dim(read_data))

  # Float32 should preserve values well
  for (ch in seq_len(ncol(orig_data))) {
    r <- cor(orig_data[, ch], read_data[, ch])
    expect_gt(r, 0.999)
  }
})

test_that("BrainVision round-trip preserves channel names", {
  pe <- make_pe_2d(n_time = 100, n_channels = 3, sr = 250)

  tmp_base <- tempfile()
  on.exit({
    unlink(paste0(tmp_base, ".vhdr"))
    unlink(paste0(tmp_base, ".vmrk"))
    unlink(paste0(tmp_base, ".eeg"))
  })

  writeBrainVision(pe, tmp_base)
  pe_read <- readBrainVision(paste0(tmp_base, ".vhdr"))

  col_data <- SummarizedExperiment::colData(pe_read)
  expect_true("label" %in% names(col_data))
  expect_equal(nrow(col_data), 3)
})

# --- writeBrainVision options ---

test_that("writeBrainVision supports different binary formats", {
  pe <- make_pe_2d(n_time = 100, n_channels = 2, sr = 250)

  for (fmt in c("IEEE_FLOAT_32", "INT_16", "INT_32")) {
    tmp_base <- tempfile()

    writeBrainVision(pe, tmp_base, binary_format = fmt)

    expect_true(file.exists(paste0(tmp_base, ".eeg")))
    pe_read <- readBrainVision(paste0(tmp_base, ".vhdr"))
    expect_s4_class(pe_read, "PhysioExperiment")

    unlink(paste0(tmp_base, ".vhdr"))
    unlink(paste0(tmp_base, ".vmrk"))
    unlink(paste0(tmp_base, ".eeg"))
  }
})

test_that("writeBrainVision with overwrite = FALSE errors on existing files", {
  pe <- make_pe_2d(n_time = 100, n_channels = 2, sr = 250)

  tmp_base <- tempfile()
  on.exit({
    unlink(paste0(tmp_base, ".vhdr"))
    unlink(paste0(tmp_base, ".vmrk"))
    unlink(paste0(tmp_base, ".eeg"))
  })

  writeBrainVision(pe, tmp_base)
  expect_error(
    writeBrainVision(pe, tmp_base, overwrite = FALSE),
    "Files already exist"
  )
})

test_that("writeBrainVision with overwrite = TRUE replaces existing files", {
  pe <- make_pe_2d(n_time = 100, n_channels = 2, sr = 250)

  tmp_base <- tempfile()
  on.exit({
    unlink(paste0(tmp_base, ".vhdr"))
    unlink(paste0(tmp_base, ".vmrk"))
    unlink(paste0(tmp_base, ".eeg"))
  })

  writeBrainVision(pe, tmp_base)
  expect_silent(writeBrainVision(pe, tmp_base, overwrite = TRUE))
})

test_that("writeBrainVision returns invisible NULL", {
  pe <- make_pe_2d(n_time = 100, n_channels = 2, sr = 250)

  tmp_base <- tempfile()
  on.exit({
    unlink(paste0(tmp_base, ".vhdr"))
    unlink(paste0(tmp_base, ".vmrk"))
    unlink(paste0(tmp_base, ".eeg"))
  })

  result <- writeBrainVision(pe, tmp_base)
  expect_null(result)
})

# --- Channel selection ---

test_that("readBrainVision with specific channels works", {
  pe <- make_pe_2d(n_time = 100, n_channels = 4, sr = 250)

  tmp_base <- tempfile()
  on.exit({
    unlink(paste0(tmp_base, ".vhdr"))
    unlink(paste0(tmp_base, ".vmrk"))
    unlink(paste0(tmp_base, ".eeg"))
  })

  writeBrainVision(pe, tmp_base)
  pe_sub <- readBrainVision(paste0(tmp_base, ".vhdr"), channels = c("Ch1", "Ch3"))

  expect_equal(ncol(SummarizedExperiment::assay(pe_sub)), 2)
})

test_that("readBrainVision errors on missing channels", {
  pe <- make_pe_2d(n_time = 100, n_channels = 2, sr = 250)

  tmp_base <- tempfile()
  on.exit({
    unlink(paste0(tmp_base, ".vhdr"))
    unlink(paste0(tmp_base, ".vmrk"))
    unlink(paste0(tmp_base, ".eeg"))
  })

  writeBrainVision(pe, tmp_base)
  expect_error(
    readBrainVision(paste0(tmp_base, ".vhdr"), channels = c("Nonexistent")),
    "Channels not found"
  )
})

# --- Header parsing ---

test_that("BrainVision header file is valid text", {
  pe <- make_pe_2d(n_time = 100, n_channels = 2, sr = 500)

  tmp_base <- tempfile()
  on.exit({
    unlink(paste0(tmp_base, ".vhdr"))
    unlink(paste0(tmp_base, ".vmrk"))
    unlink(paste0(tmp_base, ".eeg"))
  })

  writeBrainVision(pe, tmp_base)

  header_lines <- readLines(paste0(tmp_base, ".vhdr"))
  expect_true(any(grepl("Brain Vision Data Exchange Header", header_lines)))
  expect_true(any(grepl("NumberOfChannels=2", header_lines)))
  expect_true(any(grepl("SamplingInterval=", header_lines)))
  expect_true(any(grepl("\\[Channel Infos\\]", header_lines)))
})
