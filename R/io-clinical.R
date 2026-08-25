#' Clinical metadata CSV I/O and validation
#'
#' Utilities for loading and validating clinical assessment metadata so
#' physiological sessions can be linked with EDC/EHR variables using
#' `subject_id` and `visit_id`.

#' Read clinical metadata from CSV
#'
#' @param path Path to the CSV/TSV file.
#' @param col_map Optional named character vector for renaming columns.
#'   Names are source columns and values are target column names.
#' @param required_cols Required columns for validation.
#' @param date_cols Columns to parse as Date (`YYYY-MM-DD`) when present.
#' @param validate Logical; run \code{validateClinicalMetadata()} when TRUE.
#' @param sep Field separator, default `","`.
#' @param header Logical, default `TRUE`.
#' @param ... Additional arguments passed to \code{utils::read.csv()}.
#'
#' @return Data frame containing standardized clinical metadata.
#' @references
#'   Goldberger AL, et al. (2000). "PhysioBank, PhysioToolkit, and
#'   PhysioNet: components of a new research resource for complex
#'   physiologic signals." Circulation, 101(23), e215-e220.
#'   doi:10.1161/01.CIR.101.23.e215
#' @seealso \code{\link{validateClinicalMetadata}},
#'   \code{\link{mapClinicalCodes}}, \code{\link{readCSV}}
#' @export
#' @examples
#' tmp <- tempfile(fileext = ".csv")
#' write.csv(data.frame(
#'   sid = "S01",
#'   vid = "V01",
#'   scale_name = "FIM",
#'   scale_score = 90,
#'   assessment_date = "2026-01-10"
#' ), tmp, row.names = FALSE)
#'
#' df <- readClinicalMetadataCSV(
#'   tmp,
#'   col_map = c(sid = "subject_id", vid = "visit_id")
#' )
#' unlink(tmp)
readClinicalMetadataCSV <- function(path,
                                    col_map = NULL,
                                    required_cols = c("subject_id", "visit_id",
                                                      "scale_name", "scale_score"),
                                    date_cols = c("assessment_date", "visit_date"),
                                    validate = TRUE,
                                    sep = ",",
                                    header = TRUE,
                                    ...) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  x <- utils::read.csv(
    path,
    sep = sep,
    header = header,
    stringsAsFactors = FALSE,
    ...
  )

  if (!is.null(col_map)) {
    if (is.null(names(col_map)) || any(names(col_map) == "")) {
      stop("col_map must be a named character vector", call. = FALSE)
    }

    for (src in names(col_map)) {
      if (src %in% names(x)) {
        names(x)[names(x) == src] <- unname(col_map[[src]])
      }
    }
  }

  present_date_cols <- intersect(date_cols, names(x))
  if (length(present_date_cols) > 0L) {
    for (col in present_date_cols) {
      x[[col]] <- as.Date(x[[col]])
    }
  }

  if (validate) {
    validateClinicalMetadata(
      x = x,
      required_cols = required_cols,
      strict = TRUE
    )
  }

  x
}


#' Validate clinical metadata
#'
#' @param x Data frame created from EDC/EHR exports.
#' @param required_cols Required columns that must exist and be non-missing.
#' @param allowed_source_system Allowed values for `source_system` when present.
#' @param allowed_assessor_role Allowed values for `assessor_role` when present.
#' @param strict Logical; stop when validation fails.
#'
#' @return A list with validation details and an overall `valid` flag.
#' @references
#'   Goldberger AL, et al. (2000). "PhysioBank, PhysioToolkit, and
#'   PhysioNet: components of a new research resource for complex
#'   physiologic signals." Circulation, 101(23), e215-e220.
#'   doi:10.1161/01.CIR.101.23.e215
#' @seealso \code{\link{readClinicalMetadataCSV}},
#'   \code{\link{mapClinicalCodes}}, \code{\link{validateBIDS}}
#' @export
#' @examples
#' df <- data.frame(
#'   subject_id = "S01",
#'   visit_id = "V01",
#'   scale_name = "FIM",
#'   scale_score = 88,
#'   assessment_date = "2026-01-01",
#'   stringsAsFactors = FALSE
#' )
#' validateClinicalMetadata(df)
validateClinicalMetadata <- function(
    x,
    required_cols = c("subject_id", "visit_id", "scale_name", "scale_score"),
    allowed_source_system = c("EDC", "EHR", "paper_crf"),
    allowed_assessor_role = c("PT", "OT", "MD", "RN", "researcher"),
    strict = FALSE) {
  if (!is.data.frame(x)) {
    stop("x must be a data.frame", call. = FALSE)
  }

  missing_cols <- setdiff(required_cols, names(x))

  missing_required_values <- integer(0)
  if (length(missing_cols) == 0L && nrow(x) > 0L) {
    req_na <- Reduce(`|`, lapply(required_cols, function(col) {
      is.na(x[[col]]) | x[[col]] == ""
    }))
    missing_required_values <- which(req_na)
  }

  invalid_dates <- integer(0)
  date_cols <- intersect(c("assessment_date", "visit_date"), names(x))
  if (length(date_cols) > 0L && nrow(x) > 0L) {
    invalid_date_flags <- Reduce(`|`, lapply(date_cols, function(col) {
      vals <- x[[col]]
      if (inherits(vals, "Date")) {
        return(is.na(vals))
      }
      parsed <- as.Date(vals)
      !is.na(vals) & vals != "" & is.na(parsed)
    }))
    invalid_dates <- which(invalid_date_flags)
  }

  invalid_scale_score <- integer(0)
  if ("scale_score" %in% names(x) && nrow(x) > 0L) {
    score <- suppressWarnings(as.numeric(x$scale_score))
    invalid_scale_score <- which(
      !is.na(x$scale_score) & x$scale_score != "" & is.na(score)
    )
  }

  invalid_source_system <- integer(0)
  if ("source_system" %in% names(x) && nrow(x) > 0L) {
    invalid_source_system <- which(
      !is.na(x$source_system) &
        x$source_system != "" &
        !(x$source_system %in% allowed_source_system)
    )
  }

  invalid_assessor_role <- integer(0)
  if ("assessor_role" %in% names(x) && nrow(x) > 0L) {
    invalid_assessor_role <- which(
      !is.na(x$assessor_role) &
        x$assessor_role != "" &
        !(x$assessor_role %in% allowed_assessor_role)
    )
  }

  duplicate_rows <- integer(0)
  key_cols <- intersect(
    c("subject_id", "visit_id", "scale_name", "assessment_date"),
    names(x)
  )
  if (length(key_cols) >= 3L && nrow(x) > 0L) {
    key <- do.call(paste, c(x[key_cols], sep = "||"))
    duplicate_rows <- which(duplicated(key))
  }

  valid <- length(missing_cols) == 0L &&
    length(missing_required_values) == 0L &&
    length(invalid_dates) == 0L &&
    length(invalid_scale_score) == 0L &&
    length(invalid_source_system) == 0L &&
    length(invalid_assessor_role) == 0L &&
    length(duplicate_rows) == 0L

  out <- list(
    valid = valid,
    missing_columns = missing_cols,
    missing_required_rows = missing_required_values,
    invalid_date_rows = invalid_dates,
    invalid_scale_score_rows = invalid_scale_score,
    invalid_source_system_rows = invalid_source_system,
    invalid_assessor_role_rows = invalid_assessor_role,
    duplicate_rows = duplicate_rows
  )

  if (isTRUE(strict) && !isTRUE(valid)) {
    stop(
      "Clinical metadata validation failed. ",
      "missing_columns=", paste(missing_cols, collapse = ","),
      "; missing_required_rows=", length(missing_required_values),
      "; invalid_date_rows=", length(invalid_dates),
      "; invalid_scale_score_rows=", length(invalid_scale_score),
      "; invalid_source_system_rows=", length(invalid_source_system),
      "; invalid_assessor_role_rows=", length(invalid_assessor_role),
      call. = FALSE
    )
  }

  out
}


#' Harmonize clinical codes across sites
#'
#' @param x Clinical metadata data frame.
#' @param mapping Code mapping, either:
#'   1) named character vector (`names` = source code, `values` = target code), or
#'   2) data frame with columns defined by `from_col` and `to_col`.
#' @param code_col Source code column in `x`.
#' @param mapped_col Output mapped code column.
#' @param from_col Source column in mapping data.frame.
#' @param to_col Target column in mapping data.frame.
#' @param unmatched Behavior for unmatched codes: `"keep"`, `"na"`, or `"drop"`.
#'
#' @return Data frame with `mapped_col` appended.
#' @references
#'   Goldberger AL, et al. (2000). "PhysioBank, PhysioToolkit, and
#'   PhysioNet: components of a new research resource for complex
#'   physiologic signals." Circulation, 101(23), e215-e220.
#'   doi:10.1161/01.CIR.101.23.e215
#' @seealso \code{\link{readClinicalMetadataCSV}},
#'   \code{\link{validateClinicalMetadata}}
#' @export
#' @examples
#' df <- data.frame(scale_name = c("fim_total", "Berg"), stringsAsFactors = FALSE)
#' map <- c(fim_total = "FIM", Berg = "BBS")
#' mapClinicalCodes(df, map, code_col = "scale_name")
mapClinicalCodes <- function(x,
                             mapping,
                             code_col = "scale_name",
                             mapped_col = "scale_name_std",
                             from_col = "from",
                             to_col = "to",
                             unmatched = c("keep", "na", "drop")) {
  unmatched <- match.arg(unmatched)

  if (!is.data.frame(x)) {
    stop("x must be a data.frame", call. = FALSE)
  }
  if (!code_col %in% names(x)) {
    stop("code_col not found: ", code_col, call. = FALSE)
  }

  if (is.data.frame(mapping)) {
    if (!all(c(from_col, to_col) %in% names(mapping))) {
      stop("mapping data.frame must contain from_col and to_col", call. = FALSE)
    }
    lut <- stats::setNames(as.character(mapping[[to_col]]),
                           as.character(mapping[[from_col]]))
  } else if (is.character(mapping) && !is.null(names(mapping))) {
    lut <- mapping
  } else {
    stop(
      "mapping must be a named character vector or a data.frame with from/to columns",
      call. = FALSE
    )
  }

  src <- as.character(x[[code_col]])
  mapped <- unname(lut[src])
  has_match <- !is.na(mapped)

  if (unmatched == "keep") {
    mapped[!has_match] <- src[!has_match]
    out <- x
  } else if (unmatched == "na") {
    out <- x
  } else {
    out <- x[has_match, , drop = FALSE]
    mapped <- mapped[has_match]
  }

  out[[mapped_col]] <- mapped
  out
}
