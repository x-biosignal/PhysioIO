# Write electrode positions to CSV

Writes electrode positions from a PhysioExperiment to CSV.

## Usage

``` r
writeElectrodePositionsCSV(x, path, sep = ",", ...)
```

## Arguments

- x:

  A PhysioExperiment object with electrode positions.

- path:

  Output file path.

- sep:

  Column separator.

- ...:

  Additional arguments passed to write.csv.

## Value

Invisible path to the created file.

## References

Wickham H (2014). "Tidy Data." Journal of Statistical Software, 59(10),
1-23. doi:10.18637/jss.v059.i10

## See also

[`readElectrodePositionsCSV`](https://x-biosignal.github.io/PhysioIO/reference/readElectrodePositionsCSV.md),
[`writeCSV`](https://x-biosignal.github.io/PhysioIO/reference/writeCSV.md),
[`writeBIDS`](https://x-biosignal.github.io/PhysioIO/reference/writeBIDS.md)

## Examples

``` r
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
  colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
  samplingRate = 100
)
pe <- applyMontage(pe, "10-20")

# Write electrode positions
tmp <- tempfile(fileext = ".csv")
writeElectrodePositionsCSV(pe, tmp)

# Clean up
unlink(tmp)
```
