library(testthat)
library(PhysioIO)

# Check if writeBin with size=2 is supported on this platform
# Test with an integer vector like writeEDF uses, not just a scalar
.writeBin_size2_supported <- tryCatch({
  tmp <- tempfile()
  con <- file(tmp, "wb")
  on.exit({
    try(close(con), silent = TRUE)
    unlink(tmp)
  })
  # Test with integer vector similar to what writeEDF uses
  writeBin(c(0L, 1L, -1L, 32767L, -32768L), con, size = 2)
  TRUE
}, error = function(e) {
  FALSE
})

# Skip function for individual tests
skip_if_writeBin_unsupported <- function() {
  if (!.writeBin_size2_supported) {
    skip("writeBin with size=2 not supported on this platform")
  }
}

make_test_pe <- function() {
  n_samples <- 250
  n_channels <- 3

  data <- matrix(sin(seq(0, 10, length.out = n_samples * n_channels)),
                 nrow = n_samples, ncol = n_channels)

  # rowData must have n_samples rows (matching dim[1] = time points)
  row_data <- S4Vectors::DataFrame(time_idx = seq_len(n_samples))

  # colData must have n_channels rows (matching dim[2] = channels)
  col_data <- S4Vectors::DataFrame(
    label = c("Fp1", "Fp2", "Cz"),
    type = c("EEG", "EEG", "EEG"),
    unit = c("uV", "uV", "uV"),
    pos_x = c(-0.3, 0.3, 0),
    pos_y = c(0.9, 0.9, 1.0),
    pos_z = c(0, 0, 0)
  )

  # Convert to 3D array (time x channels x samples)
  assays <- S4Vectors::SimpleList(raw = array(data, dim = c(n_samples, n_channels, 1)))
  pe <- PhysioExperiment(assays, rowData = row_data, colData = col_data,
                         samplingRate = 250)

  # Add events
  events <- PhysioEvents(
    onset = c(0.1, 0.5, 0.8),
    duration = c(0.1, 0.1, 0),
    type = c("stimulus", "stimulus", "response"),
    value = c("face", "house", "button")
  )
  pe <- setEvents(pe, events)

  pe
}

test_that("writeBIDS creates directory structure", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "test")

  # Check directory structure
  expect_true(dir.exists(file.path(temp_dir, "sub-01")))
  expect_true(dir.exists(file.path(temp_dir, "sub-01", "eeg")))
})

test_that("writeBIDS creates required files", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest")

  eeg_dir <- file.path(temp_dir, "sub-01", "eeg")

  # Check for EDF file
  expect_true(file.exists(file.path(eeg_dir, "sub-01_task-rest_eeg.edf")))

  # Check for channels.tsv
  expect_true(file.exists(file.path(eeg_dir, "sub-01_task-rest_eeg_channels.tsv")))

  # Check for events.tsv
  expect_true(file.exists(file.path(eeg_dir, "sub-01_task-rest_eeg_events.tsv")))

  # Check for sidecar JSON
  expect_true(file.exists(file.path(eeg_dir, "sub-01_task-rest_eeg.json")))

  # Check for dataset_description.json
  expect_true(file.exists(file.path(temp_dir, "dataset_description.json")))
})

test_that("writeBIDS with session", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", session = "01", task = "rest")

  expect_true(dir.exists(file.path(temp_dir, "sub-01", "ses-01", "eeg")))
  expect_true(file.exists(file.path(temp_dir, "sub-01", "ses-01", "eeg",
                                     "sub-01_ses-01_task-rest_eeg.edf")))
})

test_that("writeBIDS with run number", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest", run = 1)

  expect_true(file.exists(file.path(temp_dir, "sub-01", "eeg",
                                     "sub-01_task-rest_run-01_eeg.edf")))
})

test_that("writeBIDS channels.tsv has correct format", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest")

  channels_file <- file.path(temp_dir, "sub-01", "eeg", "sub-01_task-rest_eeg_channels.tsv")
  channels <- read.delim(channels_file, stringsAsFactors = FALSE)

  expect_true("name" %in% names(channels))
  expect_true("type" %in% names(channels))
  expect_true("units" %in% names(channels))
  expect_true("sampling_frequency" %in% names(channels))

  expect_equal(nrow(channels), 3)
  expect_true("Fp1" %in% channels$name)
})

test_that("writeBIDS events.tsv has correct format", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest")

  events_file <- file.path(temp_dir, "sub-01", "eeg", "sub-01_task-rest_eeg_events.tsv")
  events <- read.delim(events_file, stringsAsFactors = FALSE)

  expect_true("onset" %in% names(events))
  expect_true("duration" %in% names(events))
  expect_true("trial_type" %in% names(events))
  expect_true("value" %in% names(events))

  expect_equal(nrow(events), 3)
})

test_that("readBIDS loads data correctly", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest")

  loaded <- readBIDS(temp_dir, subject = "01", task = "rest")

  expect_s4_class(loaded, "PhysioExperiment")
  expect_equal(nChannels(loaded), 3)
})

test_that("readBIDS loads events", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest")

  loaded <- readBIDS(temp_dir, subject = "01", task = "rest", load_events = TRUE)

  events <- getEvents(loaded)
  expect_equal(nEvents(events), 3)
})

test_that("readBIDS stores BIDS metadata", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", session = "02", task = "rest")

  loaded <- readBIDS(temp_dir, subject = "01", session = "02", task = "rest")

  meta <- S4Vectors::metadata(loaded)
  expect_equal(meta$bids$subject, "01")
  expect_equal(meta$bids$session, "02")
  expect_equal(meta$bids$task, "rest")
})

test_that("listBIDSSubjects returns subjects", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest")
  writeBIDS(pe, bids_root = temp_dir, subject = "02", task = "rest")

  subjects <- listBIDSSubjects(temp_dir)

  expect_length(subjects, 2)
  expect_true("01" %in% subjects)
  expect_true("02" %in% subjects)
})

test_that("listBIDSSessions returns sessions", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", session = "01", task = "rest")
  writeBIDS(pe, bids_root = temp_dir, subject = "01", session = "02", task = "rest")

  sessions <- listBIDSSessions(temp_dir, subject = "01")

  expect_length(sessions, 2)
  expect_true("01" %in% sessions)
  expect_true("02" %in% sessions)
})

test_that("validateBIDS detects missing description", {
  temp_dir <- tempfile()
  dir.create(temp_dir)
  dir.create(file.path(temp_dir, "sub-01"))
  on.exit(unlink(temp_dir, recursive = TRUE))

  result <- validateBIDS(temp_dir)

  expect_false(result$valid)
  expect_true(any(grepl("dataset_description.json", result$errors)))
})

test_that("validateBIDS passes for valid dataset", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest")

  result <- validateBIDS(temp_dir)

  expect_true(result$valid)
  expect_equal(result$n_subjects, 1)
})

test_that("readBIDS errors on missing directory", {
  expect_error(readBIDS("/nonexistent/path", subject = "01", task = "rest"),
               "not found")
})

test_that("writeBIDS errors on existing file without overwrite", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest")

  expect_error(
    writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest", overwrite = FALSE),
    "File exists"
  )
})

test_that("writeBIDS overwrites with flag", {
  skip_if_writeBin_unsupported()
  pe <- make_test_pe()
  temp_dir <- tempfile()
  on.exit(unlink(temp_dir, recursive = TRUE))

  writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest")

  # This should not error
  expect_no_error(
    writeBIDS(pe, bids_root = temp_dir, subject = "01", task = "rest", overwrite = TRUE)
  )
})
