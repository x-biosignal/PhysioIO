library(testthat)
library(PhysioIO)

skip_if(requireNamespace("R.matlab", quietly = TRUE),
  message = "Dependency-missing tests are only for environments without R.matlab"
)

test_that("writeMAT fails with clear error when R.matlab is unavailable", {
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(1:20, nrow = 10, ncol = 2)),
    samplingRate = 100
  )

  expect_error(
    writeMAT(pe, tempfile(fileext = ".mat")),
    "R.matlab"
  )
})

test_that("readMAT fails with clear error when R.matlab is unavailable", {
  tmp <- tempfile(fileext = ".mat")
  file.create(tmp)
  on.exit(unlink(tmp), add = TRUE)

  expect_error(
    readMAT(tmp),
    "R.matlab"
  )
})
