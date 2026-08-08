# HDF5 Backend for PhysioExperiment

Functions for reading and writing PhysioExperiment objects to HDF5
format, supporting out-of-memory operations for large datasets. Write
PhysioExperiment to HDF5

## Usage

``` r
writePhysioHDF5(
  x,
  path,
  overwrite = FALSE,
  chunk_dims = NULL,
  compression_level = 6L
)
```

## Arguments

- x:

  A PhysioExperiment object.

- path:

  Path to the output HDF5 file.

- overwrite:

  Logical. If TRUE, overwrites existing file.

- chunk_dims:

  Optional integer vector specifying chunk dimensions for HDF5 storage.
  If `NULL`, defaults are chosen automatically.

- compression_level:

  Integer compression level (0-9). Default is 6.

## Value

Invisible `NULL`. The HDF5 file is written to `path` as a side effect.

## Details

Saves a PhysioExperiment object to HDF5 format, enabling out-of-memory
access for large datasets.

## References

The HDF Group (1997-2024). "Hierarchical Data Format, version 5."
<https://www.hdfgroup.org/HDF5/>

## See also

[`readPhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/readPhysioHDF5.md),
[`isHDF5Backed`](https://x-biosignal.github.io/PhysioIO/reference/isHDF5Backed.md),
[`realizeHDF5`](https://x-biosignal.github.io/PhysioIO/reference/realizeHDF5.md),
[`writeAssayHDF5`](https://x-biosignal.github.io/PhysioIO/reference/writeAssayHDF5.md)

## Examples

``` r
# Create a PhysioExperiment
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
  samplingRate = 100
)

# Save to a temporary HDF5 file with compression
tmp <- tempfile(fileext = ".h5")
writePhysioHDF5(pe, tmp, compression_level = 6)

# Overwrite the existing file
writePhysioHDF5(pe, tmp, overwrite = TRUE)

unlink(tmp)
```
