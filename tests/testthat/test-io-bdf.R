library(testthat)
library(PhysioIO)

test_that("24-bit LE decode matches known values incl. negative two's-complement", {
  # values 0, 1, -1, 8388607 (max), -8388608 (min), 256, -256
  bytes <- as.raw(c(0, 0, 0,        # 0
                    1, 0, 0,        # 1
                    255, 255, 255,  # -1
                    255, 255, 127,  # 8388607
                    0, 0, 128,      # -8388608
                    0, 1, 0,        # 256
                    0, 255, 255))   # -256
  got <- PhysioIO:::.convert24bitToInteger(bytes, 7L)
  expect_equal(got, c(0, 1, -1, 8388607, -8388608, 256, -256))
})

test_that("bdfTriggerEvents maps trigger transitions to correct onsets", {
  status <- c(0, 0, 5, 5, 0, 0, 10, 0)          # rising to 5 @ idx3, 10 @ idx7
  ev <- bdfTriggerEvents(status, sampling_rate = 8)
  a <- as.data.frame(ev@events)
  expect_equal(a$onset, c((3 - 1) / 8, (7 - 1) / 8))    # 0.25 s, 0.75 s
  expect_equal(as.character(a$value), c("5", "10"))
  expect_equal(as.character(a$type), c("trigger", "trigger"))
  # only the low 16 bits are used; high status bits are ignored
  ev2 <- bdfTriggerEvents(c(0, bitwOr(0x10000L, 7L), 0), sampling_rate = 4)
  expect_equal(as.character(as.data.frame(ev2@events)$value), "7")
})

# hand-craft a minimal BDF (1 record, EEG + Status) matching the header layout
.craft_bdf <- function(path, eeg, status_vals, fs = 8) {
  spr <- length(eeg)
  stopifnot(length(status_vals) == spr)
  con <- file(path, "wb"); on.exit(close(con))
  pad <- function(s, n) { s <- substr(as.character(s), 1, n)
                          paste0(s, strrep(" ", n - nchar(s))) }
  ns <- 2L
  writeBin(as.raw(0xFF), con); writeBin(charToRaw("BIOSEMI"), con)
  writeBin(charToRaw(pad("patient", 80)), con)
  writeBin(charToRaw(pad("recording", 80)), con)
  writeBin(charToRaw("20.07.26"), con); writeBin(charToRaw("00.00.00"), con)
  writeBin(charToRaw(pad(256 + ns * 256, 8)), con)
  writeBin(charToRaw(pad("24BIT", 44)), con)
  writeBin(charToRaw(pad("1", 8)), con)                       # n_records
  writeBin(charToRaw(pad(as.character(spr / fs), 8)), con)    # record duration
  writeBin(charToRaw(pad(as.character(ns), 4)), con)
  labs <- c("EEG", "Status")
  for (i in 1:ns) writeBin(charToRaw(pad(labs[i], 16)), con)
  for (i in 1:ns) writeBin(charToRaw(pad("elec", 80)), con)
  for (i in 1:ns) writeBin(charToRaw(pad("uV", 8)), con)
  for (i in 1:ns) writeBin(charToRaw(pad("-1000", 8)), con)
  for (i in 1:ns) writeBin(charToRaw(pad("1000", 8)), con)
  for (i in 1:ns) writeBin(charToRaw(pad("-8388608", 8)), con)
  for (i in 1:ns) writeBin(charToRaw(pad("8388607", 8)), con)
  for (i in 1:ns) writeBin(charToRaw(pad("", 80)), con)
  for (i in 1:ns) writeBin(charToRaw(pad(as.character(spr), 8)), con)
  for (i in 1:ns) writeBin(charToRaw(pad("", 32)), con)
  enc24 <- function(v) { v <- if (v < 0) v + 16777216L else v
                         as.raw(c(v %% 256L, (v %/% 256L) %% 256L,
                                  (v %/% 65536L) %% 256L)) }
  for (v in eeg) writeBin(enc24(as.integer(v)), con)
  for (v in status_vals) writeBin(enc24(as.integer(v)), con)
  invisible(path)
}

test_that("readBDFStatus reads the raw Status channel", {
  f <- tempfile(fileext = ".bdf")
  .craft_bdf(f, eeg = c(0, 100, -100, 50, 0, 0, 0, 0),
             status_vals = c(0, 0, 5, 5, 0, 0, 10, 0), fs = 8)
  st <- readBDFStatus(f); unlink(f)
  expect_equal(st$values, c(0, 0, 5, 5, 0, 0, 10, 0))
  expect_equal(st$fs, 8)
})

test_that("readBDF attaches Status triggers as events and drops the Status channel", {
  f <- tempfile(fileext = ".bdf")
  .craft_bdf(f, eeg = c(0, 100, -100, 50, 0, 0, 0, 0),
             status_vals = c(0, 0, 5, 5, 0, 0, 10, 0), fs = 8)
  x <- readBDF(f); unlink(f)
  expect_s4_class(x, "PhysioExperiment")
  expect_equal(channelNames(x), "EEG")                 # Status excluded
  ev <- as.data.frame(getEvents(x)@events)
  expect_equal(ev$onset, c(0.25, 0.75))
  expect_equal(as.character(ev$value), c("5", "10"))
  # status = FALSE suppresses trigger extraction
  f2 <- tempfile(fileext = ".bdf")
  .craft_bdf(f2, eeg = c(0, 100, -100, 50, 0, 0, 0, 0),
             status_vals = c(0, 0, 5, 5, 0, 0, 10, 0), fs = 8)
  x2 <- readBDF(f2, status = FALSE); unlink(f2)
  expect_equal(nEvents(getEvents(x2)), 0L)
})

test_that("writeBDF -> readBDF round-trips the signal within quantization tolerance", {
  set.seed(1)
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(200 * 2) * 50, 200, 2)),
    colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2")),
    samplingRate = 256)
  f <- tempfile(fileext = ".bdf")
  writeBDF(pe, f)
  back <- readBDF(f); unlink(f)
  expect_s4_class(back, "PhysioExperiment")
  orig <- SummarizedExperiment::assay(pe, "raw")
  # writeBDF pads to whole records; compare the original samples
  got <- SummarizedExperiment::assay(back, "raw")[seq_len(nrow(orig)), , drop = FALSE]
  # BDF round-trip fidelity is limited by the 8-char physical-min/max header
  # fields (~6 significant figures), not the 24-bit quantization; error is a
  # small fraction of the signal range
  tol <- (max(orig) - min(orig)) * 1e-4
  expect_lt(max(abs(got - orig)), tol)
  expect_equal(samplingRate(back), 256)
})
