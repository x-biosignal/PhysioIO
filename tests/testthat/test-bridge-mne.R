library(testthat)
library(PhysioIO)

# The MNE-dependent tests below skip unless `reticulate` can reach a Python with
# `mne` installed (hasMNE() == TRUE); they never initialise reticulate when it
# cannot, so they are safe on CRAN / r-universe. To actually run them, point
# reticulate at a suitable interpreter, e.g.
#   RETICULATE_PYTHON=/path/to/python-with-mne Rscript -e 'devtools::test()'

make_mne_pe <- function() {
  set.seed(11)
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(300), 100, 3)),
    colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz"),
                                   type = rep("eeg", 3)),
    samplingRate = 128)
  pe <- PhysioCore::setElectrodePositions(
    pe, data.frame(x = c(-0.03, 0.03, 0), y = c(0.08, 0.08, 0),
                   z = c(0.02, 0.02, 0.09)))
  PhysioCore::setEvents(pe, PhysioCore::PhysioEvents(
    onset = c(0.1, 0.5), duration = c(0.05, 0.1),
    type = c("stim", "resp"), value = c("A", "B")))
}

test_that("MNE-computed PSD matches an independent R periodogram (validation oracle)", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  # A 10 Hz (alpha) oscillation with a per-channel amplitude gradient + noise.
  # MNE's PSD and an independent base-R periodogram must agree on the per-channel
  # alpha power (spatial pattern) -- the cross-check that lets a native op be
  # trusted against MNE. Absolute scale differs by normalisation, so we assert
  # spatial correlation, not numerical parity.
  set.seed(7); sr <- 250; n <- 2000; nch <- 8
  tt <- seq_len(n) / sr
  amp <- seq(0.5, 2, length.out = nch)
  m <- vapply(seq_len(nch),
              function(j) amp[j] * sin(2 * pi * 10 * tt) + rnorm(n, sd = 0.3),
              numeric(n))
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = m),
    colData = S4Vectors::DataFrame(label = paste0("C", seq_len(nch)),
                                   type = rep("eeg", nch)),
    samplingRate = sr)

  raw <- toMNE(pe)
  psd <- raw$compute_psd(fmin = 1, fmax = 45, verbose = FALSE)
  pdat <- psd$get_data(); freqs <- as.numeric(psd$freqs)
  mne_alpha <- rowSums(pdat[, freqs >= 8 & freqs <= 13, drop = FALSE])

  r_alpha <- vapply(seq_len(nch), function(j) {
    sp <- stats::spec.pgram(m[, j], taper = 0, fast = FALSE, detrend = FALSE,
                            plot = FALSE)
    f <- sp$freq * sr
    sum(sp$spec[f >= 8 & f <= 13])
  }, numeric(1))

  expect_gt(stats::cor(mne_alpha, r_alpha), 0.99)
})

test_that("hasMNE and pyMNEVersion report availability consistently", {
  expect_type(hasMNE(), "logical")
  v <- pyMNEVersion()
  if (hasMNE()) {
    expect_true(is.character(v) && nzchar(v))
  } else {
    expect_true(is.na(v))
  }
})

test_that("toMNE errors clearly and fromMNE is exported", {
  expect_true(is.function(toMNE))
  expect_true(is.function(fromMNE))
  expect_equal(names(formals(toMNE)), c("x", "assay"))
})

test_that("fromMNE(toMNE(pe)) reproduces data, ch_names, ch_types and sfreq", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  pe <- make_mne_pe()
  raw <- toMNE(pe)
  pe2 <- fromMNE(raw)

  expect_lt(max(abs(SummarizedExperiment::assay(pe, "raw") -
                    SummarizedExperiment::assay(pe2, "raw"))), 1e-6)
  expect_identical(as.character(SummarizedExperiment::colData(pe2)$label),
                   c("Fp1", "Fp2", "Cz"))
  expect_identical(as.character(SummarizedExperiment::colData(pe2)$type),
                   rep("eeg", 3))
  expect_equal(samplingRate(pe2), 128)
})

test_that("events survive the round-trip as MNE annotations", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  pe <- make_mne_pe()
  pe2 <- fromMNE(toMNE(pe))
  e1 <- PhysioCore::getEvents(pe)@events
  e2 <- PhysioCore::getEvents(pe2)@events
  expect_equal(e2$onset, e1$onset)
  expect_equal(e2$duration, e1$duration)
  expect_identical(e2$type, e1$type)
  expect_identical(e2$value, e1$value)   # type + value packed into description
})

test_that("annotations are visible on the MNE object itself", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  pe <- make_mne_pe()
  raw <- toMNE(pe)
  ann <- raw$annotations
  expect_equal(as.numeric(reticulate::py_to_r(ann$onset)), c(0.1, 0.5))
  expect_equal(as.numeric(reticulate::py_to_r(ann$duration)), c(0.05, 0.1))
})

test_that("the electrode montage round-trips both directions", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  pe <- make_mne_pe()
  pe2 <- fromMNE(toMNE(pe))
  p1 <- PhysioCore::getElectrodePositions(pe)[, c("x", "y", "z")]
  p2 <- PhysioCore::getElectrodePositions(pe2)[, c("x", "y", "z")]
  expect_lt(max(abs(as.matrix(p1) - as.matrix(p2))), 1e-6)
})

test_that("fromMNE records the import in provenance", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  pe2 <- fromMNE(toMNE(make_mne_pe()))
  prov <- PhysioCore::provenance(pe2)
  expect_true("fromMNE" %in% prov$activity)
})

test_that("objects without montage or events round-trip cleanly", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(40), 20, 2)),
    colData = S4Vectors::DataFrame(label = c("EMG1", "ECG1"),
                                   type = c("emg", "ecg")),
    samplingRate = 500)
  pe2 <- fromMNE(toMNE(pe))
  expect_lt(max(abs(SummarizedExperiment::assay(pe, "raw") -
                    SummarizedExperiment::assay(pe2, "raw"))), 1e-6)
  expect_identical(as.character(SummarizedExperiment::colData(pe2)$type),
                   c("emg", "ecg"))
  expect_equal(PhysioCore::nEvents(PhysioCore::getEvents(pe2)), 0L)
})

test_that("non-MNE channel types map to misc", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(40), 20, 2)),
    colData = S4Vectors::DataFrame(label = c("m1", "m2"),
                                   type = c("marker", "imu")),
    samplingRate = 100)
  pe2 <- fromMNE(toMNE(pe))
  expect_identical(as.character(SummarizedExperiment::colData(pe2)$type),
                   c("misc", "misc"))
})

# ---- regression tests for adversarial-review findings (DMIO-15) -------------

test_that("empty MNE annotation descriptions import as empty type, not NA", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  mne <- reticulate::import("mne")
  np <- reticulate::import("numpy")
  info <- mne$create_info(ch_names = list("a", "b"), sfreq = 100,
                          ch_types = list("eeg", "eeg"))
  raw <- mne$io$RawArray(np$array(t(matrix(rnorm(40), 20, 2))), info,
                         verbose = FALSE)
  raw$set_annotations(mne$Annotations(onset = 0.1, duration = 0,
                                      description = list("")), verbose = FALSE)
  pe <- fromMNE(raw)
  ev <- PhysioCore::getEvents(pe)@events
  expect_equal(nrow(ev), 1L)
  expect_false(is.na(ev$type))
  expect_identical(ev$type, "")
})

test_that("an event value containing the separator still round-trips", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  sep <- intToUtf8(31L)   # ASCII unit separator, the internal delimiter
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(40), 20, 2)),
    colData = S4Vectors::DataFrame(label = c("a", "b"), type = c("eeg", "eeg")),
    samplingRate = 100)
  pe <- PhysioCore::setEvents(pe, PhysioCore::PhysioEvents(
    onset = 0.05, duration = 0, type = "cond", value = paste0("x", sep, "y")))
  pe2 <- fromMNE(toMNE(pe))
  ev <- PhysioCore::getEvents(pe2)@events
  expect_identical(ev$type, "cond")
  expect_identical(ev$value, paste0("x", sep, "y"))
})

test_that("toMNE warns when an event falls outside the recording", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(40), 20, 2)),
    colData = S4Vectors::DataFrame(label = c("a", "b"), type = c("eeg", "eeg")),
    samplingRate = 100)  # 0.2 s recording
  pe <- PhysioCore::setEvents(pe, PhysioCore::PhysioEvents(
    onset = 999, duration = 0, type = "late", value = ""))
  expect_warning(toMNE(pe), "outside the")
})

test_that("toMNE rejects duplicate channel names and invalid sampling rate", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  pe_dup <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(40), 20, 2)),
    colData = S4Vectors::DataFrame(label = c("Cz", "Cz"), type = c("eeg", "eeg")),
    samplingRate = 100)
  expect_error(toMNE(pe_dup), "unique channel names")
  pe_sr <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(40), 20, 2)),
    colData = S4Vectors::DataFrame(label = c("a", "b"), type = c("eeg", "eeg")),
    samplingRate = NA_real_)
  expect_error(toMNE(pe_sr), "positive value")
})

test_that("NA event value round-trips to an empty string (MNE has no NA)", {
  skip_if_not(hasMNE(), "Python 'mne' not available")
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(40), 20, 2)),
    colData = S4Vectors::DataFrame(label = c("a", "b"), type = c("eeg", "eeg")),
    samplingRate = 100)
  pe <- PhysioCore::setEvents(pe, PhysioCore::PhysioEvents(
    onset = 0.05, duration = 0, type = "cue", value = NA_character_))
  pe2 <- fromMNE(toMNE(pe))
  ev <- PhysioCore::getEvents(pe2)@events
  expect_identical(ev$type, "cue")
  expect_identical(ev$value, "")
})
