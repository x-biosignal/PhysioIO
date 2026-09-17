library(testthat)
library(PhysioIO)

with_mocked_mat_backend <- function(code) {
  old_opts <- options(
    PhysioIO.readMatFun = function(path) readRDS(path),
    PhysioIO.writeMatFun = function(path, export_list) saveRDS(export_list, path)
  )
  on.exit(options(old_opts), add = TRUE)
  force(code)
}

test_that("writeMAT/readMAT round-trip works with mocked backend", {
  with_mocked_mat_backend({
    set.seed(123)
    original <- PhysioExperiment(
      assays = S4Vectors::SimpleList(raw = matrix(rnorm(100), nrow = 50, ncol = 2)),
      colData = S4Vectors::DataFrame(label = c("Ch1", "Ch2")),
      samplingRate = 256
    )

    tmp <- tempfile(fileext = ".mat")
    on.exit(unlink(tmp), add = TRUE)

    writeMAT(original, tmp)
    restored <- readMAT(tmp)

    expect_s4_class(restored, "PhysioExperiment")
    expect_equal(samplingRate(restored), 256)
    expect_equal(dim(SummarizedExperiment::assay(restored)), c(50, 2))
    expect_equal(
      unname(SummarizedExperiment::assay(restored)),
      unname(SummarizedExperiment::assay(original)),
      tolerance = 1e-10
    )
  })
})

test_that("writeMAT metadata and custom variable settings are respected", {
  with_mocked_mat_backend({
    pe <- PhysioExperiment(
      assays = S4Vectors::SimpleList(raw = matrix(1:20, nrow = 10, ncol = 2)),
      colData = S4Vectors::DataFrame(label = c("Ch1", "Ch2")),
      samplingRate = 100
    )
    pe <- setEvents(pe, PhysioEvents(
      onset = c(1.0, 2.0),
      duration = c(0.1, 0.1),
      type = c("stim", "resp"),
      value = c("1", "2")
    ))

    tmp <- tempfile(fileext = ".mat")
    on.exit(unlink(tmp), add = TRUE)

    writeMAT(pe, tmp, data_var = "EEG_data")
    out <- readRDS(tmp)
    expect_true("EEG_data" %in% names(out))
    expect_true("srate" %in% names(out))
    expect_true("channels" %in% names(out))
    expect_true("event_onset" %in% names(out))
    expect_true("event_type" %in% names(out))

    writeMAT(pe, tmp, include_metadata = FALSE)
    out2 <- readRDS(tmp)
    expect_true("data" %in% names(out2))
    expect_false("srate" %in% names(out2))
    expect_false("channels" %in% names(out2))
  })
})

test_that("readMAT supports explicit variable mapping and errors clearly", {
  with_mocked_mat_backend({
    tmp <- tempfile(fileext = ".mat")
    on.exit(unlink(tmp), add = TRUE)

    saveRDS(list(signal = matrix(rnorm(50), nrow = 10, ncol = 5), fs = 100), tmp)
    pe <- readMAT(tmp, data_var = "signal", sr_var = "fs")
    expect_s4_class(pe, "PhysioExperiment")
    expect_equal(samplingRate(pe), 100)
    expect_equal(dim(SummarizedExperiment::assay(pe)), c(10, 5))

    saveRDS(list(other_var = 1:3), tmp)
    expect_error(readMAT(tmp, data_var = "nonexistent"), "Could not find data variable")
  })
})
