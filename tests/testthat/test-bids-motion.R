library(testthat)
library(PhysioIO)

.mk_motion <- function(n = 100, sr = 60) {
  PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(n * 3), n, 3)),
    colData = S4Vectors::DataFrame(
      label = c("LWristX", "LWristY", "LWristZ"),
      type = rep("POS", 3), unit = rep("m", 3),
      tracked_point = rep("LeftWrist", 3), component = c("x", "y", "z")),
    samplingRate = sr)
}

test_that("Motion-BIDS write then read reproduces points, rate and units", {
  root <- tempfile("bids"); dir.create(root)
  mot <- .mk_motion()
  writeBIDSMotion(mot, root, subject = "01", task = "walk",
                  tracking_system = "optical")
  back <- readBIDSMotion(root, subject = "01", task = "walk")

  expect_s4_class(back, "PhysioExperiment")
  expect_equal(samplingRate(back), 60)
  expect_equal(channelNames(back), c("LWristX", "LWristY", "LWristZ"))
  cd <- SummarizedExperiment::colData(back)
  expect_equal(as.character(cd$tracked_point), rep("LeftWrist", 3))
  expect_equal(as.character(cd$component), c("x", "y", "z"))
  expect_equal(as.character(cd$unit), rep("m", 3))
  expect_equal(unname(SummarizedExperiment::assay(back, "raw")),
               unname(SummarizedExperiment::assay(mot, "raw")))
  # sidecar carries the tracking system name
  expect_equal(S4Vectors::metadata(back)$tracking_system_name, "optical")
})

test_that("the _motion.tsv is headerless per the Motion-BIDS spec", {
  root <- tempfile("bids"); dir.create(root)
  writeBIDSMotion(.mk_motion(n = 5), root, subject = "01", task = "walk",
                  tracking_system = "optical")
  tsv <- list.files(file.path(root, "sub-01", "motion"),
                    pattern = "_motion\\.tsv$", full.names = TRUE)
  first <- readLines(tsv, n = 1)
  # first line is data (numeric fields), not a header of channel names
  expect_false(grepl("LWrist", first))
  expect_equal(length(strsplit(first, "\t")[[1]]), 3L)
})

test_that("_physio.tsv.gz round-trips with correct StartTime and SamplingFrequency", {
  root <- tempfile("bids"); dir.create(root)
  phys <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(200 * 2), 200, 2)),
    colData = S4Vectors::DataFrame(label = c("respiratory", "cardiac")),
    samplingRate = 100)
  gz <- writeBIDSPhysio(phys, root, subject = "01", task = "walk",
                        start_time = 2.5)
  expect_true(grepl("_physio\\.tsv\\.gz$", gz))
  # the sidecar has the required fields
  json <- jsonlite::fromJSON(sub("\\.tsv\\.gz$", ".json", gz))
  expect_equal(json$SamplingFrequency, 100)
  expect_equal(json$StartTime, 2.5)
  expect_equal(unlist(json$Columns), c("respiratory", "cardiac"))

  back <- readBIDSPhysio(gz)
  expect_equal(samplingRate(back), 100)
  expect_equal(S4Vectors::metadata(back)$bids_start_time, 2.5)
  expect_equal(channelNames(back), c("respiratory", "cardiac"))
  expect_equal(unname(SummarizedExperiment::assay(back, "raw")),
               unname(SummarizedExperiment::assay(phys, "raw")))
})

test_that("attachBIDSPhysio yields a multi-rate aligned stream honouring StartTime", {
  root <- tempfile("bids"); dir.create(root)
  main <- .mk_motion(sr = 60)
  phys <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(200 * 2), 200, 2)),
    colData = S4Vectors::DataFrame(label = c("resp", "cardiac")),
    samplingRate = 100)
  gz <- writeBIDSPhysio(phys, root, subject = "01", task = "walk", start_time = 1.5)
  back <- readBIDSPhysio(gz)

  mr <- attachBIDSPhysio(main, back)
  expect_s4_class(mr, "MultiRatePhysioExperiment")
  expect_setequal(PhysioCore::streamNames(mr), c("recording", "physio"))
  expect_equal(unname(PhysioCore::streamRates(mr)["physio"]), 100)
  expect_equal(PhysioCore::commonClock(mr)$offsets[["physio"]], 1.5)
})

test_that("derivatives write GeneratedBy from provenance and round-trip", {
  root <- tempfile("bids"); dir.create(root)
  proc <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(100 * 2), 100, 2)),
    colData = S4Vectors::DataFrame(label = c("a", "b")), samplingRate = 100)
  proc <- PhysioCore::logStep(proc, "filterSignals", params = list(low = 0.1))
  proc <- PhysioCore::logStep(proc, "detrend")

  dr <- file.path(root, "derivatives", "physio-clean")
  writeBIDSDerivative(proc, dr, subject = "01", task = "rest", desc = "clean")

  dd <- jsonlite::fromJSON(file.path(dr, "dataset_description.json"))
  expect_equal(dd$DatasetType, "derivative")
  expect_true(grepl("filterSignals", dd$GeneratedBy$Description))
  expect_true(grepl("detrend", dd$GeneratedBy$Description))

  derivs <- readBIDSDerivatives(dr, subject = "01")
  expect_equal(names(derivs), "clean")
  expect_s4_class(derivs[["clean"]], "PhysioExperiment")
  expect_equal(samplingRate(derivs[["clean"]]), 100)
})

test_that("validateBIDS accepts a Motion-BIDS dataset", {
  root <- tempfile("bids"); dir.create(root)
  writeBIDSMotion(.mk_motion(), root, subject = "01", task = "walk",
                  tracking_system = "optical")
  v <- validateBIDS(root)
  expect_true(v$valid)
  expect_length(v$errors, 0L)
})

# ---- regression tests for adversarial-review findings ----------------------

test_that("derivative filenames put desc after run (BIDS canonical order)", {
  root <- tempfile("bids"); dir.create(root)
  proc <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)),
    colData = S4Vectors::DataFrame(label = c("a", "b")), samplingRate = 100)
  dr <- file.path(root, "derivatives", "clean")
  writeBIDSDerivative(proc, dr, subject = "01", task = "rest", desc = "clean",
                      run = 3)
  f <- list.files(file.path(dr, "sub-01", "beh"), pattern = "\\.tsv\\.gz$")
  expect_match(f, "_run-03_desc-clean_physio\\.tsv\\.gz$")
})

test_that("motion auto-pick does not confuse task-walk with task-walking", {
  root <- tempfile("bids"); dir.create(root)
  writeBIDSMotion(.mk_motion(), root, subject = "01", task = "walk",
                  tracking_system = "optical")
  writeBIDSMotion(.mk_motion(), root, subject = "01", task = "walking",
                  tracking_system = "optical")
  x <- readBIDSMotion(root, subject = "01", task = "walk")   # not "walking"
  expect_equal(ncol(SummarizedExperiment::assay(x, "raw")), 3L)
})

test_that("ambiguous motion files require a tracking_system", {
  root <- tempfile("bids"); dir.create(root)
  writeBIDSMotion(.mk_motion(), root, subject = "01", task = "walk",
                  tracking_system = "optical")
  writeBIDSMotion(.mk_motion(), root, subject = "01", task = "walk",
                  tracking_system = "imu")
  expect_error(readBIDSMotion(root, subject = "01", task = "walk"),
               "specify tracking_system")
  # disambiguated read works
  x <- readBIDSMotion(root, subject = "01", task = "walk",
                      tracking_system = "imu")
  expect_s4_class(x, "PhysioExperiment")
})

test_that("writeBIDSDerivative refuses to overwrite by default", {
  root <- tempfile("bids"); dir.create(root)
  proc <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)),
    colData = S4Vectors::DataFrame(label = c("a", "b")), samplingRate = 100)
  dr <- file.path(root, "derivatives", "clean")
  writeBIDSDerivative(proc, dr, subject = "01", task = "rest", desc = "clean")
  expect_error(
    writeBIDSDerivative(proc, dr, subject = "01", task = "rest", desc = "clean"),
    "file exists")
  expect_silent(
    writeBIDSDerivative(proc, dr, subject = "01", task = "rest", desc = "clean",
                        overwrite = TRUE))
})

test_that("readBIDSDerivatives only returns desc-bearing files, correctly keyed", {
  root <- tempfile("bids"); dir.create(root)
  proc <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)),
    colData = S4Vectors::DataFrame(label = c("a", "b")), samplingRate = 100)
  dr <- file.path(root, "derivatives", "clean")
  writeBIDSDerivative(proc, dr, subject = "01", task = "rest", desc = "clean")
  # a desc-less physio dropped in the same beh dir must be ignored, not mislabeled
  writeBIDSPhysio(proc, dr, subject = "01", task = "rest")
  derivs <- readBIDSDerivatives(dr, subject = "01")
  expect_equal(names(derivs), "clean")
})

test_that("readBIDSMotion errors on a channels.tsv / data column mismatch", {
  root <- tempfile("bids"); dir.create(root)
  writeBIDSMotion(.mk_motion(), root, subject = "01", task = "walk",
                  tracking_system = "optical")
  chf <- list.files(file.path(root, "sub-01", "motion"),
                    pattern = "_channels\\.tsv$", full.names = TRUE)
  ch <- utils::read.delim(chf, stringsAsFactors = FALSE)
  utils::write.table(ch[1:2, ], chf, sep = "\t", row.names = FALSE, quote = FALSE)
  expect_error(readBIDSMotion(root, subject = "01", task = "walk"),
               "channels.tsv describes")
})

test_that("the generated dataset passes bids-validator when available", {
  skip_if_not(nzchar(Sys.which("bids-validator")), "bids-validator not installed")
  root <- tempfile("bids"); dir.create(root)
  writeBIDSMotion(.mk_motion(), root, subject = "01", task = "walk",
                  tracking_system = "optical")
  out <- suppressWarnings(system2("bids-validator", c(root, "--json"),
                                  stdout = TRUE, stderr = TRUE))
  res <- tryCatch(jsonlite::fromJSON(paste(out, collapse = "")),
                  error = function(e) NULL)
  skip_if(is.null(res), "bids-validator output not parseable")
  n_err <- if (!is.null(res$issues$errors)) length(res$issues$errors) else 0L
  expect_equal(n_err, 0L)
})
