library(testthat)
library(PhysioIO)

# Standing external-parity guards for the binary readers.
#
# Both defects fixed in 0.2.7 / 0.2.8 (readWFDB's baseline default, readEDF's
# fused EDF+ annotations) shared a blind spot: they produced plausible values,
# the writers could never emit the input that triggers them, so a round trip
# could not reach them, and NOTHING compared the reader against the format's
# reference implementation. These tests are that missing comparison.
#
# They skip unless reticulate can reach a Python carrying the reference library,
# so CRAN / r-universe are unaffected. To run them locally:
#   RETICULATE_PYTHON=/path/to/python Rscript -e "testthat::test_file(...)"

.py_mod <- function(mod) {
  if (!requireNamespace("reticulate", quietly = TRUE)) return(FALSE)
  isTRUE(tryCatch(reticulate::py_module_available(mod), error = function(e) FALSE))
}

# Records tracked in the agent evaluation corpus; skipped when absent (the
# package alone ships only the bundled record-100 excerpt).
.eval_dir <- function(sub) {
  p <- file.path("..", "..", "..", "agent", "eval", "data", sub)
  if (dir.exists(p)) normalizePath(p) else NA_character_
}

test_that("readWFDB reproduces wfdb-python across every tracked header style", {
  skip_if_not(.py_mod("wfdb"), "Python 'wfdb' not available")
  mitdb <- .eval_dir("mitdb"); fant <- .eval_dir("fantasia"); bidmc <- .eval_dir("bidmc")
  skip_if(is.na(mitdb), "tracked WFDB records not available")

  recs <- c(file.path(mitdb, "100"))                       # bare gain + ADC zero 1024
  if (!is.na(fant))  recs <- c(recs, file.path(fant,  "f1y01"))   # bare gain, ADC zero 0
  if (!is.na(bidmc)) recs <- c(recs, file.path(bidmc, "bidmc01")) # explicit (baseline), non-integer gain
  wfdb <- reticulate::import("wfdb")

  for (rec in recs) {
    ref <- wfdb$rdrecord(rec, sampto = 5000L)$p_signal
    ours <- as.matrix(SummarizedExperiment::assay(readWFDB(rec), "raw"))[seq_len(5000), , drop = FALSE]
    expect_equal(ncol(ours), ncol(ref))
    expect_lt(max(abs(ours - ref)), 1e-9)                  # physical units, bit-for-bit
  }
})

test_that("readEDF reproduces MNE signals and EDF+ annotations", {
  skip_if_not(.py_mod("mne"), "Python 'mne' not available")
  eeg <- .eval_dir("eegmmidb"); sleep <- .eval_dir("sleep-edfx")
  skip_if(is.na(eeg) && is.na(sleep), "tracked EDF records not available")
  mne <- reticulate::import("mne")

  if (!is.na(eeg)) {
    f <- file.path(eeg, "S002R02.edf")
    if (file.exists(f)) {
      ref <- mne$io$read_raw_edf(f, preload = TRUE, verbose = "ERROR")$get_data()
      ours <- as.matrix(SummarizedExperiment::assay(readEDF(f), "raw"))
      # the ecosystem reports microvolts, MNE volts
      expect_lt(max(abs(t(ours) * 1e-6 - ref[, seq_len(nrow(ours))])), 1e-12)
    }
  }

  if (!is.na(sleep)) {
    # A hypnogram stores a whole night's TALs in ONE data record: the input the
    # writer can never produce, and the shape that fused 154 events into 1.
    f <- file.path(sleep, "SC4001EC-Hypnogram.edf")
    if (file.exists(f)) {
      ref <- mne$read_annotations(f)
      ev <- as.data.frame(S4Vectors::metadata(readEDF(f))$events@events)
      expect_equal(nrow(ev), length(ref$onset))
      expect_equal(as.numeric(ev$onset), as.numeric(ref$onset))
      expect_equal(as.numeric(ev$duration), as.numeric(ref$duration))
    }
  }
})
