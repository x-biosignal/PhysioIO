# Harmonize clinical codes across sites

Harmonize clinical codes across sites

## Usage

``` r
mapClinicalCodes(
  x,
  mapping,
  code_col = "scale_name",
  mapped_col = "scale_name_std",
  from_col = "from",
  to_col = "to",
  unmatched = c("keep", "na", "drop")
)
```

## Arguments

- x:

  Clinical metadata data frame.

- mapping:

  Code mapping, either:

  1.  named character vector (`names` = source code, `values` = target
      code), or

  2.  data frame with columns defined by `from_col` and `to_col`.

- code_col:

  Source code column in `x`.

- mapped_col:

  Output mapped code column.

- from_col:

  Source column in mapping data.frame.

- to_col:

  Target column in mapping data.frame.

- unmatched:

  Behavior for unmatched codes: `"keep"`, `"na"`, or `"drop"`.

## Value

Data frame with `mapped_col` appended.

## References

Goldberger AL, et al. (2000). "PhysioBank, PhysioToolkit, and PhysioNet:
components of a new research resource for complex physiologic signals."
Circulation, 101(23), e215-e220. doi:10.1161/01.CIR.101.23.e215

## See also

[`readClinicalMetadataCSV`](https://x-biosignal.github.io/PhysioIO/reference/readClinicalMetadataCSV.md),
[`validateClinicalMetadata`](https://x-biosignal.github.io/PhysioIO/reference/validateClinicalMetadata.md)

## Examples

``` r
df <- data.frame(scale_name = c("fim_total", "Berg"), stringsAsFactors = FALSE)
map <- c(fim_total = "FIM", Berg = "BBS")
mapClinicalCodes(df, map, code_col = "scale_name")
#>   scale_name scale_name_std
#> 1  fim_total            FIM
#> 2       Berg            BBS
```
