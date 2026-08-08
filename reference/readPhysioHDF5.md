# Read PhysioExperiment from HDF5

Reads a PhysioExperiment object from HDF5 format. By default, returns
DelayedArray-backed assays for out-of-memory processing.

## Usage

``` r
readPhysioHDF5(path, as_delayed = TRUE)
```

## Arguments

- path:

  Path to the HDF5 file.

- as_delayed:

  Logical. If TRUE (default), returns DelayedArray-backed assays. If
  FALSE, loads data into memory.

## Value

A
[`PhysioExperiment`](https://x-biosignal.r-universe.dev/PhysioCore/reference/PhysioExperiment-class.html)
object. When `as_delayed = TRUE`, assays are `HDF5Array` objects
enabling out-of-memory access; when `FALSE`, assays are standard
in-memory arrays.

## References

The HDF Group (1997-2024). "Hierarchical Data Format, version 5."
<https://www.hdfgroup.org/HDF5/>

## See also

[`writePhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/writePhysioHDF5.md),
[`isHDF5Backed`](https://x-biosignal.github.io/PhysioIO/reference/isHDF5Backed.md),
[`realizeHDF5`](https://x-biosignal.github.io/PhysioIO/reference/realizeHDF5.md),
[`writeAssayHDF5`](https://x-biosignal.github.io/PhysioIO/reference/writeAssayHDF5.md)

## Examples

``` r
# Write a small PhysioExperiment to a temporary HDF5 file
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
  samplingRate = 100
)
tmp <- tempfile(fileext = ".h5")
writePhysioHDF5(pe, tmp)

# Read it back with the DelayedArray backend (out-of-memory)
pe_delayed <- readPhysioHDF5(tmp)
isHDF5Backed(pe_delayed)  # TRUE
#> [1] TRUE

# Read it back into memory
pe_mem <- readPhysioHDF5(tmp, as_delayed = FALSE)
isHDF5Backed(pe_mem)  # FALSE
#> [1] FALSE

unlink(tmp)
```
