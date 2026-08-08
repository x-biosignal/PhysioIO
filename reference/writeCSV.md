# Write PhysioExperiment to CSV file

Writes physiological signal data to a CSV file.

## Usage

``` r
writeCSV(
  x,
  path,
  format = c("wide", "long"),
  include_time = TRUE,
  assay_name = NULL,
  sep = ",",
  ...
)
```

## Arguments

- x:

  A PhysioExperiment object.

- path:

  Output file path.

- format:

  Output format: "wide" (time x channels) or "long".

- include_time:

  Logical. If TRUE, includes a time column.

- assay_name:

  Assay to export. If NULL, uses default assay.

- sep:

  Column separator. Default is ",".

- ...:

  Additional arguments passed to write.csv/write.table.

## Value

Invisible path to the created file.

## References

Wickham H (2014). "Tidy Data." Journal of Statistical Software, 59(10),
1-23. doi:10.18637/jss.v059.i10

## See also

[`readCSV`](https://x-biosignal.github.io/PhysioIO/reference/readCSV.md),
[`writeEventsCSV`](https://x-biosignal.github.io/PhysioIO/reference/writeEventsCSV.md),
[`writeEDF`](https://x-biosignal.github.io/PhysioIO/reference/writeEDF.md),
[`writePhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/writePhysioHDF5.md)

## Examples

``` r
# Create example data
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
  colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
  samplingRate = 100
)

# Write to temporary CSV file
tmp <- tempfile(fileext = ".csv")
writeCSV(pe, tmp)

# Write in long format
writeCSV(pe, tmp, format = "long")

# Clean up
unlink(tmp)
```
