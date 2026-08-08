# Realize HDF5-backed data to memory

Loads HDF5-backed assays into memory as regular arrays.

## Usage

``` r
realizeHDF5(x, assays = NULL)
```

## Arguments

- x:

  A PhysioExperiment object.

- assays:

  Optional character vector of assay names to realize. If NULL, realizes
  all assays.

## Value

A
[`PhysioExperiment`](https://x-biosignal.r-universe.dev/PhysioCore/reference/PhysioExperiment-class.html)
object with the specified assays realized as in-memory arrays.

## References

The HDF Group (1997-2024). "Hierarchical Data Format, version 5."
<https://www.hdfgroup.org/HDF5/>

## See also

[`readPhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/readPhysioHDF5.md),
[`writePhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/writePhysioHDF5.md),
[`isHDF5Backed`](https://x-biosignal.github.io/PhysioIO/reference/isHDF5Backed.md)

## Examples

``` r
# Write and read back HDF5-backed data
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
  samplingRate = 100
)
tmp <- tempfile(fileext = ".h5")
writePhysioHDF5(pe, tmp)
pe_delayed <- readPhysioHDF5(tmp)

# Realize all assays to memory
pe_mem <- realizeHDF5(pe_delayed)
isHDF5Backed(pe_mem)  # FALSE
#> [1] FALSE

unlink(tmp)
```
