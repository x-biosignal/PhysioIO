# Read electrode positions from CSV

Reads electrode positions from a CSV file with x, y, z coordinates.

## Usage

``` r
readElectrodePositionsCSV(
  path,
  name_col = "name",
  x_col = "x",
  y_col = "y",
  z_col = "z",
  sep = ",",
  ...
)
```

## Arguments

- path:

  Path to the CSV file.

- name_col:

  Name of the electrode name column.

- x_col:

  Name of the x coordinate column.

- y_col:

  Name of the y coordinate column.

- z_col:

  Name of the z coordinate column.

- sep:

  Column separator.

- ...:

  Additional arguments passed to read.csv.

## Value

A data.frame with electrode positions.

## References

Wickham H (2014). "Tidy Data." Journal of Statistical Software, 59(10),
1-23. doi:10.18637/jss.v059.i10

## See also

[`writeElectrodePositionsCSV`](https://x-biosignal.github.io/PhysioIO/reference/writeElectrodePositionsCSV.md),
[`readCSV`](https://x-biosignal.github.io/PhysioIO/reference/readCSV.md),
[`readBIDS`](https://x-biosignal.github.io/PhysioIO/reference/readBIDS.md)

## Examples

``` r
# Write electrode positions to a temporary CSV, then read them back
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
  colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
  samplingRate = 100
)
pe <- applyMontage(pe, "10-20")
tmp <- tempfile(fileext = ".csv")
writeElectrodePositionsCSV(pe, tmp)

positions <- readElectrodePositionsCSV(tmp)
unlink(tmp)
```
