library(testthat)
library(PhysioIO)

.mk_prov_pe <- function() {
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), nrow = 10, ncol = 2)),
    samplingRate = 100
  )
  pe <- appendProvenance(pe, activity = "import",
                         params = list(source = "sub-01_eeg.edf"),
                         input_assay = "sub-01_eeg.edf", output_assay = "raw",
                         package = "PhysioIO", software_version = "0.2.0")
  pe <- appendProvenance(pe, activity = "filterSignals",
                         params = list(low = 1, high = 40),
                         input_assay = "raw", output_assay = "filtered")
  pe <- logStep(pe, "averageEpochs")   # no params -> empty params
  pe
}

test_that("writeProv -> readProv round-trips PROV-JSON exactly", {
  pe <- .mk_prov_pe()
  orig <- provenance(pe)
  tf <- tempfile(fileext = ".prov.json")
  writeProv(pe, tf, format = "prov-json")
  back <- readProv(tf)
  unlink(tf)
  expect_equal(back, orig)
})

test_that("writeProv -> readProv round-trips JSON-LD exactly", {
  pe <- .mk_prov_pe()
  orig <- provenance(pe)
  tf <- tempfile(fileext = ".jsonld")
  writeProv(pe, tf, format = "json-ld")
  back <- readProv(tf)
  unlink(tf)
  expect_equal(back, orig)
})

test_that("writeProv -> readProv round-trips PROV-N exactly", {
  pe <- .mk_prov_pe()
  orig <- provenance(pe)
  tf <- tempfile(fileext = ".provn")
  writeProv(pe, tf, format = "prov-n")
  back <- readProv(tf)
  unlink(tf)
  expect_equal(back, orig)
})

test_that("the emitted PROV-JSON carries a valid PROV activity/entity/agent graph", {
  pe <- .mk_prov_pe()
  tf <- tempfile(fileext = ".json")
  writeProv(pe, tf, format = "prov-json")
  doc <- jsonlite::fromJSON(tf, simplifyVector = FALSE)
  unlink(tf)
  n <- nrow(provenance(pe))
  expect_length(doc$activity, n)
  expect_length(doc$entity, n)
  expect_length(doc$agent, n)
  # every generation edge links an entity to an activity that exist
  for (g in doc$wasGeneratedBy) {
    expect_true(g[["prov:entity"]] %in% names(doc$entity))
    expect_true(g[["prov:activity"]] %in% names(doc$activity))
  }
  for (a in doc$wasAssociatedWith) {
    expect_true(a[["prov:activity"]] %in% names(doc$activity))
    expect_true(a[["prov:agent"]] %in% names(doc$agent))
  }
  # activities carry PROV timing
  expect_true(all(vapply(doc$activity, function(a)
    !is.null(a[["prov:startTime"]]) && !is.null(a[["prov:endTime"]]), logical(1))))
})

test_that("the emitted PROV-JSON validates against the W3C PROV-JSON schema", {
  skip_if_not_installed("jsonvalidate")
  schema <- system.file("schema/prov-json-schema.json", package = "PhysioIO")
  skip_if(schema == "", "bundled schema not found")
  pe <- .mk_prov_pe()
  tf <- tempfile(fileext = ".json")
  writeProv(pe, tf, format = "prov-json")
  json <- paste(readLines(tf, warn = FALSE), collapse = "\n")
  unlink(tf)
  ok <- tryCatch(
    jsonvalidate::json_validate(json, schema, engine = "ajv", verbose = TRUE),
    error = function(e) NA)
  if (is.na(ok)) {
    ok <- jsonvalidate::json_validate(json, schema)   # fall back to default engine
  }
  expect_true(as.logical(ok))
})

test_that("empty provenance round-trips to an empty table", {
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)),
    samplingRate = 100
  )
  for (fmt in c("prov-json", "json-ld", "prov-n")) {
    tf <- tempfile()
    writeProv(pe, tf, format = fmt)
    back <- readProv(tf)
    unlink(tf)
    expect_equal(nrow(back), 0L)
    expect_true(all(c("activity", "entity", "params_json") %in% names(back)))
  }
})

test_that("writePhysioHDF5 bundles a PROV-JSON provenance sidecar", {
  skip_if_not_installed("rhdf5")
  pe <- .mk_prov_pe()
  h5 <- tempfile(fileext = ".h5")
  writePhysioHDF5(pe, h5)
  side <- paste0(tools::file_path_sans_ext(h5), ".prov.json")
  expect_true(file.exists(side))
  expect_equal(readProv(side), provenance(pe))
  unlink(c(h5, side))
})

test_that("the sidecar is a silent no-op when there is no provenance", {
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)),
    samplingRate = 100
  )
  base <- tempfile()
  expect_null(PhysioIO:::.writeProvSidecar(pe, paste0(base, ".h5")))
  expect_false(file.exists(paste0(base, ".prov.json")))
})
