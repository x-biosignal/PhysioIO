library(testthat)
library(PhysioIO)

test_that("format 212 decodes hand-crafted bytes to the exact reference samples", {
  # three frames of two signals, interleaved: (100,-1)(-50,1)(2047,-2048)
  # 12-bit packing per the WFDB spec (independent of writeWFDB):
  dat_bytes <- as.raw(c(100, 240, 255,   # (100, -1)
                        206, 15, 1,      # (-50, 1)
                        255, 135, 0))    # (2047, -2048)
  d <- tempfile()
  writeBin(dat_bytes, paste0(d, ".dat"))
  writeLines(c(
    sprintf("%s 2 360 3", basename(d)),
    sprintf("%s.dat 212 200(0)/mV 12 0 0 0 0 A", basename(d)),
    sprintf("%s.dat 212 200(0)/mV 12 0 0 0 0 B", basename(d))),
    paste0(d, ".hea"))

  x <- readWFDB(d)
  unlink(paste0(d, c(".hea", ".dat")))
  raw_adu <- SummarizedExperiment::assay(x, "raw") * 200   # gain 200, baseline 0
  expect_equal(round(raw_adu[, 1]), c(100, -50, 2047))     # signal A
  expect_equal(round(raw_adu[, 2]), c(-1, 1, -2048))       # signal B
  expect_equal(channelNames(x), c("A", "B"))
  expect_equal(samplingRate(x), 360)
})

test_that("readWFDB reads the bundled record 100 fixture", {
  rec <- sub("\\.hea$", "", system.file("extdata", "100.hea", package = "PhysioIO"))
  skip_if(rec == "" || !file.exists(paste0(rec, ".hea")), "fixture not installed")
  x <- readWFDB(rec)
  expect_s4_class(x, "PhysioExperiment")
  d <- SummarizedExperiment::assay(x, "raw")
  expect_equal(dim(d), c(5000L, 2L))                 # first 5000 samples, 2 leads
  expect_equal(samplingRate(x), 360)
  expect_equal(channelNames(x), c("MLII", "V5"))
  expect_true(all(is.finite(d)))
})

test_that("writeWFDB -> readWFDB round-trips every format within quantization tolerance", {
  set.seed(1)
  ranges <- list(`16` = 15000, `61` = 15000, `80` = 100, `212` = 1500,
                 `24` = 1e6, `32` = 1e7)
  for (fmt in c(16L, 61L, 80L, 212L, 24L, 32L)) {
    rng <- ranges[[as.character(fmt)]]
    adu <- matrix(sample(-rng:rng, 400 * 2, replace = TRUE), 400, 2)
    phys <- adu / 200
    pe <- PhysioExperiment(
      assays = S4Vectors::SimpleList(raw = phys),
      colData = S4Vectors::DataFrame(label = c("MLII", "V5")),
      samplingRate = 360)
    rec <- tempfile()
    writeWFDB(pe, rec, format = fmt, gain = 200, baseline = 0)
    back <- readWFDB(rec)
    unlink(paste0(rec, c(".hea", ".dat")))
    err <- max(abs(SummarizedExperiment::assay(back, "raw") - phys))
    expect_lt(err, 1 / 200 + 1e-9)                   # within one ADU
  }
})

test_that("annotation round-trip reproduces symbols and sample offsets exactly", {
  ev <- PhysioEvents(
    onset = c(10, 370, 700, 1200, 5000, 9000), duration = 0,
    type = c("N", "V", "N", "A", "N", "V"),
    value = c("", "", "aux1", "", "", "note"))
  af <- tempfile(fileext = ".atr")
  writeWFDBAnnotation(ev, af)
  ann <- readWFDBAnnotation(af)
  unlink(af)
  a <- as.data.frame(ann@events)
  expect_equal(as.integer(a$onset), c(10L, 370L, 700L, 1200L, 5000L, 9000L))
  expect_equal(as.character(a$type), c("N", "V", "N", "A", "N", "V"))
  expect_equal(as.character(a$value)[a$onset == 700], "aux1")
  expect_equal(as.character(a$value)[a$onset == 9000], "note")
})

test_that("annotations with large sample gaps (SKIP) round-trip", {
  ev <- PhysioEvents(onset = c(5, 200000, 500000), duration = 0,
                     type = c("N", "V", "N"))
  af <- tempfile(fileext = ".qrs")
  writeWFDBAnnotation(ev, af)
  a <- as.data.frame(readWFDBAnnotation(af)@events)
  unlink(af)
  expect_equal(as.integer(a$onset), c(5L, 200000L, 500000L))
  expect_equal(as.character(a$type), c("N", "V", "N"))
})

test_that("listWFDBRecords parses a RECORDS file", {
  f <- tempfile()
  writeLines(c("100", "101", "# a comment", "", "102"), f)
  expect_equal(listWFDBRecords(f), c("100", "101", "102"))
  unlink(f)
})

# ---- regression tests for adversarial-review findings ----------------------

test_that("writeWFDB errors on out-of-range ADUs instead of silently wrapping", {
  pe <- PhysioExperiment(S4Vectors::SimpleList(raw = matrix(200, 10, 2)),
                         samplingRate = 360)                # 200 * gain 200 = 40000
  expect_error(writeWFDB(pe, tempfile(), format = 16, gain = 200), "out of range")
})

test_that("readWFDB derives nsamp when the header omits it", {
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20) / 10, 10, 2)),
    colData = S4Vectors::DataFrame(label = c("A", "B")), samplingRate = 250)
  rec <- tempfile()
  writeWFDB(pe, rec, format = 16, gain = 200)
  h <- readLines(paste0(rec, ".hea"))
  h[1] <- sub("^(\\S+ \\S+ \\S+) \\S+$", "\\1", h[1])       # strip the nsamp field
  writeLines(h, paste0(rec, ".hea"))
  back <- readWFDB(rec)
  unlink(paste0(rec, c(".hea", ".dat")))
  expect_equal(nrow(SummarizedExperiment::assay(back, "raw")), 10L)
})

test_that("very large annotation gaps (>2^31 samples) round-trip via SKIP", {
  ev <- PhysioEvents(onset = c(5, 3e9), duration = 0, type = c("N", "V"))
  af <- tempfile(fileext = ".atr")
  writeWFDBAnnotation(ev, af)
  a <- as.data.frame(readWFDBAnnotation(af)@events)
  unlink(af)
  expect_equal(a$onset, c(5, 3e9))
})

test_that("writeWFDB preserves the channel unit in the header", {
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20) / 10, 10, 2)),
    colData = S4Vectors::DataFrame(label = c("A", "B"), unit = c("uV", "uV")),
    samplingRate = 250)
  rec <- tempfile()
  writeWFDB(pe, rec, format = 16, gain = 200)
  back <- readWFDB(rec)
  unlink(paste0(rec, c(".hea", ".dat")))
  expect_equal(as.character(SummarizedExperiment::colData(back)$unit),
               c("uV", "uV"))
})

test_that("readWFDB rejects unsupported format modifiers", {
  d <- tempfile()
  writeBin(as.raw(rep(0, 16)), paste0(d, ".dat"))
  writeLines(c(sprintf("%s 1 360 4", basename(d)),
               sprintf("%s.dat 16x2 200/mV 16 0 0 0 0 A", basename(d))),
             paste0(d, ".hea"))
  expect_error(readWFDB(d), "samples-per-frame")
  unlink(paste0(d, c(".hea", ".dat")))
})

test_that("empty/unknown annotation symbols do not truncate the file at EOF", {
  ev <- PhysioEvents(onset = c(0, 100, 200), duration = 0, type = c("", "N", ""))
  af <- tempfile(fileext = ".atr")
  writeWFDBAnnotation(ev, af)
  a <- as.data.frame(readWFDBAnnotation(af)@events)
  unlink(af)
  expect_equal(as.integer(a$onset), c(0L, 100L, 200L))     # all 3, no truncation
})
