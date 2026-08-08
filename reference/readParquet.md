# Read a PhysioExperiment from a Parquet dataset directory

Inverse of
[`writeParquet()`](https://x-biosignal.github.io/PhysioIO/reference/writeParquet.md):
reconstructs a `PhysioExperiment` (or `MultiRatePhysioExperiment`) from
a directory written by
[`writeParquet()`](https://x-biosignal.github.io/PhysioIO/reference/writeParquet.md).

## Usage

``` r
readParquet(dir)
```

## Arguments

- dir:

  A directory written by
  [`writeParquet()`](https://x-biosignal.github.io/PhysioIO/reference/writeParquet.md).

## Value

A `PhysioExperiment` or `MultiRatePhysioExperiment`.

## See also

[`writeParquet()`](https://x-biosignal.github.io/PhysioIO/reference/writeParquet.md)

## Examples

``` r
if (requireNamespace("arrow", quietly = TRUE)) {
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(30), 10, 3)),
    samplingRate = 256)
  d <- tempfile("pe-parquet")
  writeParquet(pe, d)
  readParquet(d)
}
#> class: PhysioExperiment
#> dim: 10 x 3 
#> assays(1): raw
#> samplingRate: 256 Hz
#> channels(3): Ch1, Ch2, Ch3
```
