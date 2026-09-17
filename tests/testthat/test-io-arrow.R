library(testthat)
library(PhysioIO)

make_arrow_pe <- function() {
  set.seed(7)
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(
      raw = matrix(rnorm(30), 10, 3),
      filtered = matrix(rnorm(30), 10, 3)),
    colData = S4Vectors::DataFrame(
      label = c("Fp1", "Fp2", "Cz"), type = rep("eeg", 3),
      unit = rep("uV", 3)),
    rowData = S4Vectors::DataFrame(idx = seq_len(10)),
    metadata = list(reference = "Cz", note = "hi"),
    samplingRate = 100)
  pe <- PhysioCore::logStep(pe, "filterSignals", params = list(low = 1, high = 40))
  pe <- PhysioCore::logStep(pe, "detrend")
  PhysioCore::setEvents(pe, PhysioCore::PhysioEvents(
    onset = c(1, 2), duration = c(0.1, 0.2),
    type = c("stim", "resp"), value = c("A", "B")))
}

test_that("writeParquet then readParquet reproduces a PhysioExperiment exactly", {
  skip_if_not_installed("arrow")
  pe <- make_arrow_pe()
  d <- tempfile("pq")
  writeParquet(pe, d)
  expect_true(file.exists(file.path(d, "manifest.json")))
  pe2 <- readParquet(d)

  expect_s4_class(pe2, "PhysioExperiment")
  # assays reproduced exactly
  for (a in c("raw", "filtered")) {
    expect_identical(unname(SummarizedExperiment::assay(pe2, a)),
                     unname(SummarizedExperiment::assay(pe, a)))
  }
  # colData / rowData reproduced exactly
  expect_identical(SummarizedExperiment::colData(pe2),
                   SummarizedExperiment::colData(pe))
  expect_identical(SummarizedExperiment::rowData(pe2),
                   SummarizedExperiment::rowData(pe))
  # sampling rates (global and per-assay)
  expect_equal(samplingRate(pe2), samplingRate(pe))
  expect_identical(PhysioCore::assaySamplingRates(pe2),
                   PhysioCore::assaySamplingRates(pe))
  # events
  expect_identical(PhysioCore::getEvents(pe2)@events,
                   PhysioCore::getEvents(pe)@events)
  # provenance reproduced exactly
  expect_identical(PhysioCore::provenance(pe2), PhysioCore::provenance(pe))
  # metadata scalars
  expect_equal(S4Vectors::metadata(pe2)$reference, "Cz")
  expect_equal(S4Vectors::metadata(pe2)$note, "hi")
})

test_that("writeParquet round-trips a minimal object with no colData/events/prov", {
  skip_if_not_installed("arrow")
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(as.numeric(1:20), 10, 2)),
    samplingRate = 250)
  d <- tempfile("pq")
  writeParquet(pe, d)
  pe2 <- readParquet(d)
  expect_identical(unname(SummarizedExperiment::assay(pe2, "raw")),
                   unname(SummarizedExperiment::assay(pe, "raw")))
  expect_equal(samplingRate(pe2), 250)
  expect_equal(ncol(pe2), 2L)
})

test_that("writeParquet preserves a 3D assay's shape", {
  skip_if_not_installed("arrow")
  arr <- array(rnorm(4 * 3 * 2), dim = c(4, 3, 2))
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = arr),
    samplingRate = 100)
  d <- tempfile("pq")
  writeParquet(pe, d)
  pe2 <- readParquet(d)
  expect_equal(dim(SummarizedExperiment::assay(pe2, "raw")), c(4L, 3L, 2L))
  expect_identical(unname(as.array(SummarizedExperiment::assay(pe2, "raw"))),
                   unname(arr))
})

test_that("writeParquet round-trips a MultiRatePhysioExperiment", {
  skip_if_not_installed("arrow")
  main <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)),
    colData = S4Vectors::DataFrame(label = c("a", "b")), samplingRate = 100)
  an <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(40), 20, 2)),
    colData = S4Vectors::DataFrame(label = c("Fx", "Fy")), samplingRate = 200)
  mr <- PhysioCore::MultiRatePhysioExperiment(recording = main, analog = an,
                                              offsets = c(analog = 0.5))
  d <- tempfile("mrpq")
  writeParquet(mr, d)
  mr2 <- readParquet(d)

  expect_s4_class(mr2, "MultiRatePhysioExperiment")
  expect_identical(PhysioCore::streamNames(mr2), PhysioCore::streamNames(mr))
  expect_identical(PhysioCore::streamRates(mr2), PhysioCore::streamRates(mr))
  expect_identical(PhysioCore::commonClock(mr2), PhysioCore::commonClock(mr))
  expect_identical(
    unname(SummarizedExperiment::assay(PhysioCore::streams(mr2)[["analog"]], "raw")),
    unname(SummarizedExperiment::assay(PhysioCore::streams(mr)[["analog"]], "raw")))
})

test_that("writeParquet refuses to overwrite a non-empty directory by default", {
  skip_if_not_installed("arrow")
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)),
    samplingRate = 100)
  d <- tempfile("pq")
  writeParquet(pe, d)
  expect_error(writeParquet(pe, d), "not empty")
  expect_silent(writeParquet(pe, d, overwrite = TRUE))
})

test_that("readParquet rejects a directory without a manifest", {
  skip_if_not_installed("arrow")
  d <- tempfile("nope"); dir.create(d)
  expect_error(readParquet(d), "manifest")
})

test_that("a DuckDB query over the Parquet backend matches in-memory aggregates", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  pe <- make_arrow_pe()
  d <- tempfile("pq")
  writeParquet(pe, d)

  con <- connectDatabase(":memory:")
  on.exit(disconnectDatabase(con), add = TRUE)
  registerParquetAssay(con, d, view_name = "signals")

  raw <- SummarizedExperiment::assay(pe, "raw")
  q <- DBI::dbGetQuery(con,
    "SELECT AVG(ch1) AS m1, SUM(ch2) AS s2, COUNT(*) AS n FROM signals")
  expect_equal(q$n, nrow(raw))
  expect_equal(q$m1, mean(raw[, 1]))
  expect_equal(q$s2, sum(raw[, 2]))
})

test_that("registerExperiment gains a Parquet backend registered as a DuckDB view", {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  pe <- make_arrow_pe()
  con <- connectDatabase(":memory:")
  on.exit(disconnectDatabase(con), add = TRUE)
  initPhysioSchema(con)
  d <- tempfile("pq")
  eid <- registerExperiment(con, pe, experiment_id = "exp1",
                            subject_id = "s1", task = "rest", parquet_dir = d)
  expect_equal(eid, "exp1")
  q <- DBI::dbGetQuery(con, "SELECT AVG(ch1) AS m1 FROM exp1_signals")
  expect_equal(q$m1, mean(SummarizedExperiment::assay(pe, "raw")[, 1]))
})

# ---- regression tests for adversarial-review findings (DMIO-14) -------------

test_that("a plain object round-trips identically without injecting metadata keys", {
  skip_if_not_installed("arrow")
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(30), 10, 3)),
    samplingRate = 100)
  # no metadata, no custom per-assay rate: metadata must stay empty
  d <- tempfile("pq")
  writeParquet(pe, d)
  pe2 <- readParquet(d)
  expect_identical(S4Vectors::metadata(pe2), S4Vectors::metadata(pe))
  expect_false("assay_sampling_rates" %in% names(S4Vectors::metadata(pe2)))
  expect_identical(pe2, pe)
})

test_that("a genuinely custom per-assay rate is preserved", {
  skip_if_not_installed("arrow")
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2),
                                   env = matrix(rnorm(20), 10, 2)),
    samplingRate = 100)
  pe <- PhysioCore::setAssaySamplingRate(pe, "env", 25)
  d <- tempfile("pq")
  writeParquet(pe, d)
  pe2 <- readParquet(d)
  expect_identical(PhysioCore::assaySamplingRates(pe2),
                   PhysioCore::assaySamplingRates(pe))
  expect_equal(unname(PhysioCore::assaySamplingRates(pe2)["env"]), 25)
})

test_that("provenance raw entries round-trip with exact types (POSIXct, int/double)", {
  skip_if_not_installed("arrow")
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)),
    samplingRate = 100)
  pe <- PhysioCore::logStep(pe, "filter",
                            params = list(low = 1, high = 40, order = 4L))
  d <- tempfile("pq")
  writeParquet(pe, d)
  pe2 <- readParquet(d)
  e1 <- S4Vectors::metadata(pe)[["provenance"]]
  e2 <- S4Vectors::metadata(pe2)[["provenance"]]
  expect_identical(e2, e1)
  expect_s3_class(e2[[1]]$startedAtTime, "POSIXct")
  expect_identical(typeof(e2[[1]]$params$order), typeof(e1[[1]]$params$order))
})

test_that("complex metadata round-trips exactly (types, precision, nesting, quotes)", {
  skip_if_not_installed("arrow")
  meta <- list(
    intval = 42L, dblval = pi, bignum = 1.234567890123456e-300,
    intvec = 1:5, strvec = c("a", "b"), quoted = "he said \"hi\"\\n",
    nested = list(a = 1L, b = c(2.5, 3.5)), dt = as.Date("2021-06-15"))
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)),
    metadata = meta, samplingRate = 100)
  d <- tempfile("pq")
  writeParquet(pe, d)
  pe2 <- readParquet(d)
  for (k in names(meta)) {
    expect_identical(S4Vectors::metadata(pe2)[[k]], meta[[k]])
  }
})

test_that("writeParquet(overwrite=TRUE) does not leak stale assays", {
  skip_if_not_installed("arrow")
  pe_ab <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(1, 4, 2),
                                   filtered = matrix(2, 4, 2)),
    samplingRate = 10)
  pe_a <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(3, 4, 2)), samplingRate = 10)
  d <- tempfile("pq")
  writeParquet(pe_ab, d)
  writeParquet(pe_a, d, overwrite = TRUE)
  expect_false(file.exists(file.path(d, "assays", "filtered.parquet")))
  pe2 <- readParquet(d)
  expect_identical(SummarizedExperiment::assayNames(pe2), "raw")
})
