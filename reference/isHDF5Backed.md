# Check if assays are HDF5-backed

Tests whether the default assay of a PhysioExperiment is stored as an
HDF5-backed DelayedArray.

## Usage

``` r
isHDF5Backed(x)
```

## Arguments

- x:

  A PhysioExperiment object.

## Value

Logical scalar; `TRUE` if the default assay inherits from `HDF5Array` or
`DelayedArray`, `FALSE` otherwise.

## References

The HDF Group (1997-2024). "Hierarchical Data Format, version 5."
<https://www.hdfgroup.org/HDF5/>

## See also

[`readPhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/readPhysioHDF5.md),
[`writePhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/writePhysioHDF5.md),
[`realizeHDF5`](https://x-biosignal.github.io/PhysioIO/reference/realizeHDF5.md)

## Examples

``` r
# Regular in-memory PhysioExperiment
pe <- PhysioExperiment(
  assays = list(raw = matrix(1:100, nrow = 10)),
  samplingRate = 100
)
isHDF5Backed(pe)  # FALSE
#> [1] FALSE
```
