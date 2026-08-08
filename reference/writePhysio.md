# Basic read/write helpers

These helper functions provide a lightweight interface to serialise and
deserialise `PhysioExperiment` objects to RDS files. They act as
placeholders for richer IO backends that can be developed later.

## Usage

``` r
writePhysio(x, path)

readPhysio(path)
```

## Arguments

- x:

  A `PhysioExperiment` object.

- path:

  Path to an `.rds` file.

## Value

`readPhysio()` returns a
[`PhysioExperiment`](https://x-biosignal.r-universe.dev/PhysioCore/reference/PhysioExperiment-class.html)
object. `writePhysio()` returns the input object invisibly.

## References

Wickham, H. (2014). "Tidy Data." Journal of Statistical Software,
59(10), 1-23. doi:10.18637/jss.v059.i10

## See also

[`readEDF`](https://x-biosignal.github.io/PhysioIO/reference/readEDF.md),
[`readPhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/readPhysioHDF5.md),
[`readCSV`](https://x-biosignal.github.io/PhysioIO/reference/readCSV.md),
[`readMAT`](https://x-biosignal.github.io/PhysioIO/reference/readMAT.md)

## Examples

``` r
# Create a PhysioExperiment object
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
  samplingRate = 256
)

# Write to a temporary file
tmp <- tempfile(fileext = ".rds")
writePhysio(pe, tmp)

# Read it back
pe_loaded <- readPhysio(tmp)
samplingRate(pe_loaded)
#> [1] 256

# Clean up
unlink(tmp)
```
