# Clinical metadata CSV I/O and validation

Utilities for loading and validating clinical assessment metadata so
physiological sessions can be linked with EDC/EHR variables using
`subject_id` and `visit_id`. Read clinical metadata from CSV

## Usage

``` r
readClinicalMetadataCSV(
  path,
  col_map = NULL,
  required_cols = c("subject_id", "visit_id", "scale_name", "scale_score"),
  date_cols = c("assessment_date", "visit_date"),
  validate = TRUE,
  sep = ",",
  header = TRUE,
  ...
)
```

## Arguments

- path:

  Path to the CSV/TSV file.

- col_map:

  Optional named character vector for renaming columns. Names are source
  columns and values are target column names.

- required_cols:

  Required columns for validation.

- date_cols:

  Columns to parse as Date (`YYYY-MM-DD`) when present.

- validate:

  Logical; run
  [`validateClinicalMetadata()`](https://x-biosignal.github.io/PhysioIO/reference/validateClinicalMetadata.md)
  when TRUE.

- sep:

  Field separator, default `","`.

- header:

  Logical, default `TRUE`.

- ...:

  Additional arguments passed to
  [`utils::read.csv()`](https://rdrr.io/r/utils/read.table.html).

## Value

Data frame containing standardized clinical metadata.

## References

Goldberger AL, et al. (2000). "PhysioBank, PhysioToolkit, and PhysioNet:
components of a new research resource for complex physiologic signals."
Circulation, 101(23), e215-e220. doi:10.1161/01.CIR.101.23.e215

## See also

[`validateClinicalMetadata`](https://x-biosignal.github.io/PhysioIO/reference/validateClinicalMetadata.md),
[`mapClinicalCodes`](https://x-biosignal.github.io/PhysioIO/reference/mapClinicalCodes.md),
[`readCSV`](https://x-biosignal.github.io/PhysioIO/reference/readCSV.md)

## Examples

``` r
tmp <- tempfile(fileext = ".csv")
write.csv(data.frame(
  sid = "S01",
  vid = "V01",
  scale_name = "FIM",
  scale_score = 90,
  assessment_date = "2026-01-10"
), tmp, row.names = FALSE)

df <- readClinicalMetadataCSV(
  tmp,
  col_map = c(sid = "subject_id", vid = "visit_id")
)
unlink(tmp)
```
