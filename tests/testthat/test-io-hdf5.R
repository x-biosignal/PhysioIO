library(testthat)
library(PhysioIO)

skip_if_not_installed("rhdf5")
skip_if_not_installed("HDF5Array")

make_hdf5_test_pe <- function() {
  set.seed(123)
  data_raw <- matrix(rnorm(200), nrow = 100, ncol = 2)
  data_filt <- matrix(rnorm(200), nrow = 100, ncol = 2)

  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = data_raw, filtered = data_filt),
    rowData = S4Vectors::DataFrame(time_idx = seq_len(100)),
    colData = S4Vectors::DataFrame(
      label = c("C1", "C2"),
      type = c("EEG", "EEG"),
      idx = c(1L, 2L)
    ),
    metadata = list(session = "test"),
    samplingRate = 250
  )

  pe <- setEvents(pe, PhysioEvents(
    onset = c(0.2, 0.7),
    duration = c(0, 0),
    type = c("stimulus", "response"),
    value = c("1", "1")
  ))

  pe
}

test_that("writePhysioHDF5 and readPhysioHDF5 round-trip in-memory", {
  pe <- make_hdf5_test_pe()
  tmp <- tempfile(fileext = ".h5")
  on.exit(unlink(tmp), add = TRUE)

  writePhysioHDF5(pe, tmp, overwrite = TRUE)
  expect_true(file.exists(tmp))

  loaded <- readPhysioHDF5(tmp, as_delayed = FALSE)
  expect_s4_class(loaded, "PhysioExperiment")
  expect_equal(samplingRate(loaded), 250)
  expect_equal(sort(SummarizedExperiment::assayNames(loaded)), c("filtered", "raw"))
  expect_equal(dim(SummarizedExperiment::assay(loaded, "raw")), c(100, 2))
  expect_equal(
    unname(SummarizedExperiment::assay(loaded, "raw")),
    unname(SummarizedExperiment::assay(pe, "raw")),
    tolerance = 1e-10
  )
  expect_equal(channelNames(loaded), c("C1", "C2"))
  expect_equal(nEvents(getEvents(loaded)), 2)
})

test_that("readPhysioHDF5 returns delayed backend and realizeHDF5 materializes", {
  pe <- make_hdf5_test_pe()
  tmp <- tempfile(fileext = ".h5")
  on.exit(unlink(tmp), add = TRUE)

  writePhysioHDF5(pe, tmp, overwrite = TRUE)

  delayed <- readPhysioHDF5(tmp, as_delayed = TRUE)
  expect_true(isHDF5Backed(delayed))

  realized <- realizeHDF5(delayed)
  expect_false(isHDF5Backed(realized))
  expect_equal(
    unname(SummarizedExperiment::assay(realized, "raw")),
    unname(SummarizedExperiment::assay(pe, "raw")),
    tolerance = 1e-10
  )
})

test_that("writePhysioHDF5 overwrite behavior is respected", {
  pe <- make_hdf5_test_pe()
  tmp <- tempfile(fileext = ".h5")
  on.exit(unlink(tmp), add = TRUE)

  writePhysioHDF5(pe, tmp, overwrite = TRUE)
  expect_error(
    writePhysioHDF5(pe, tmp, overwrite = FALSE),
    "already exists"
  )
  expect_no_error(writePhysioHDF5(pe, tmp, overwrite = TRUE))
})

test_that("writeAssayHDF5 replaces an existing assay dataset", {
  pe <- make_hdf5_test_pe()
  tmp <- tempfile(fileext = ".h5")
  on.exit(unlink(tmp), add = TRUE)

  writePhysioHDF5(pe, tmp, overwrite = TRUE)

  updated <- pe
  SummarizedExperiment::assay(updated, "filtered") <- matrix(42, nrow = 100, ncol = 2)
  writeAssayHDF5(updated, tmp, "filtered")

  loaded <- readPhysioHDF5(tmp, as_delayed = FALSE)
  expect_equal(
    unname(SummarizedExperiment::assay(loaded, "filtered")),
    unname(matrix(42, nrow = 100, ncol = 2))
  )
})
