# Validate clinical metadata

Validate clinical metadata

## Usage

``` r
validateClinicalMetadata(
  x,
  required_cols = c("subject_id", "visit_id", "scale_name", "scale_score"),
  allowed_source_system = c("EDC", "EHR", "paper_crf"),
  allowed_assessor_role = c("PT", "OT", "MD", "RN", "researcher"),
  strict = FALSE
)
```

## Arguments

- x:

  Data frame created from EDC/EHR exports.

- required_cols:

  Required columns that must exist and be non-missing.

- allowed_source_system:

  Allowed values for `source_system` when present.

- allowed_assessor_role:

  Allowed values for `assessor_role` when present.

- strict:

  Logical; stop when validation fails.

## Value

A list with validation details and an overall `valid` flag.

## References

Goldberger AL, et al. (2000). "PhysioBank, PhysioToolkit, and PhysioNet:
components of a new research resource for complex physiologic signals."
Circulation, 101(23), e215-e220. doi:10.1161/01.CIR.101.23.e215

## See also

[`readClinicalMetadataCSV`](https://x-biosignal.github.io/PhysioIO/reference/readClinicalMetadataCSV.md),
[`mapClinicalCodes`](https://x-biosignal.github.io/PhysioIO/reference/mapClinicalCodes.md),
[`validateBIDS`](https://x-biosignal.github.io/PhysioIO/reference/validateBIDS.md)

## Examples

``` r
df <- data.frame(
  subject_id = "S01",
  visit_id = "V01",
  scale_name = "FIM",
  scale_score = 88,
  assessment_date = "2026-01-01",
  stringsAsFactors = FALSE
)
validateClinicalMetadata(df)
#> $valid
#> [1] TRUE
#> 
#> $missing_columns
#> character(0)
#> 
#> $missing_required_rows
#> integer(0)
#> 
#> $invalid_date_rows
#> integer(0)
#> 
#> $invalid_scale_score_rows
#> integer(0)
#> 
#> $invalid_source_system_rows
#> integer(0)
#> 
#> $invalid_assessor_role_rows
#> integer(0)
#> 
#> $duplicate_rows
#> integer(0)
#> 
```
