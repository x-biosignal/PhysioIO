# Tests for clinical metadata utilities

test_that("readClinicalMetadataCSV renames columns and parses dates", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  raw <- data.frame(
    sid = c("S01", "S02"),
    vid = c("V01", "V01"),
    scale_name = c("FIM", "BBS"),
    scale_score = c(90, 45),
    assessment_date = c("2026-01-10", "2026-01-11"),
    stringsAsFactors = FALSE
  )
  utils::write.csv(raw, tmp, row.names = FALSE)

  out <- readClinicalMetadataCSV(
    path = tmp,
    col_map = c(sid = "subject_id", vid = "visit_id")
  )

  expect_true(all(c("subject_id", "visit_id", "scale_name", "scale_score") %in%
                  names(out)))
  expect_true(inherits(out$assessment_date, "Date"))
  expect_equal(nrow(out), 2)
})

test_that("validateClinicalMetadata identifies invalid rows", {
  x <- data.frame(
    subject_id = c("S01", "S01"),
    visit_id = c("V01", "V01"),
    scale_name = c("FIM", "FIM"),
    scale_score = c("90", "bad"),
    assessment_date = c("2026-01-10", "invalid-date"),
    assessor_role = c("PT", "UNKNOWN"),
    source_system = c("EDC", "bad_source"),
    stringsAsFactors = FALSE
  )

  v <- validateClinicalMetadata(x)

  expect_false(v$valid)
  expect_equal(v$invalid_scale_score_rows, 2)
  expect_equal(v$invalid_date_rows, 2)
  expect_equal(v$invalid_assessor_role_rows, 2)
  expect_equal(v$invalid_source_system_rows, 2)
  expect_length(v$duplicate_rows, 0)
})

test_that("validateClinicalMetadata detects duplicate key rows", {
  x <- data.frame(
    subject_id = c("S01", "S01"),
    visit_id = c("V01", "V01"),
    scale_name = c("FIM", "FIM"),
    scale_score = c(90, 92),
    assessment_date = c("2026-01-10", "2026-01-10"),
    stringsAsFactors = FALSE
  )

  v <- validateClinicalMetadata(x)
  expect_false(v$valid)
  expect_equal(v$duplicate_rows, 2)
})

test_that("readClinicalMetadataCSV fails in strict mode when invalid", {
  tmp <- tempfile(fileext = ".csv")
  on.exit(unlink(tmp))

  raw <- data.frame(
    subject_id = "S01",
    visit_id = "V01",
    scale_name = "FIM",
    scale_score = "invalid",
    stringsAsFactors = FALSE
  )
  utils::write.csv(raw, tmp, row.names = FALSE)

  expect_error(
    readClinicalMetadataCSV(tmp),
    "Clinical metadata validation failed"
  )
})

test_that("mapClinicalCodes supports vector and data.frame mappings", {
  x <- data.frame(scale_name = c("fim_total", "berg", "other"),
                  stringsAsFactors = FALSE)

  vec_map <- c(fim_total = "FIM", berg = "BBS")
  out_vec <- mapClinicalCodes(x, vec_map, unmatched = "keep")
  expect_equal(out_vec$scale_name_std, c("FIM", "BBS", "other"))

  df_map <- data.frame(from = c("fim_total", "berg"),
                       to = c("FIM", "BBS"),
                       stringsAsFactors = FALSE)
  out_drop <- mapClinicalCodes(x, df_map, unmatched = "drop")
  expect_equal(nrow(out_drop), 2)
  expect_equal(out_drop$scale_name_std, c("FIM", "BBS"))
})
