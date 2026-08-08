# Write assay to HDF5 file

Writes a single assay to an existing HDF5 file.

## Usage

``` r
writeAssayHDF5(x, path, assay_name, compression_level = 6L)
```

## Arguments

- x:

  A PhysioExperiment object.

- path:

  Path to the HDF5 file.

- assay_name:

  Character string naming the assay to write.

- compression_level:

  Integer compression level (0-9).

## Value

Invisible `NULL`. The assay is written to the HDF5 file as a side
effect.

## References

The HDF Group (1997-2024). "Hierarchical Data Format, version 5."
<https://www.hdfgroup.org/HDF5/>

## See also

[`writePhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/writePhysioHDF5.md),
[`readPhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/readPhysioHDF5.md),
[`realizeHDF5`](https://x-biosignal.github.io/PhysioIO/reference/realizeHDF5.md)

## Examples

``` r
# Create a PhysioExperiment and write it to a temporary HDF5 file
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
  samplingRate = 100
)
tmp <- tempfile(fileext = ".h5")
writePhysioHDF5(pe, tmp)

# Add a second assay to the object and write only that assay to the file
SummarizedExperiment::assay(pe, "scaled") <-
  SummarizedExperiment::assay(pe, "raw") * 2
writeAssayHDF5(pe, tmp, "scaled")

unlink(tmp)
```
