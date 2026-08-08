# Write PhysioExperiment to MATLAB .mat file

Saves a PhysioExperiment object to MATLAB .mat format.

## Usage

``` r
writeMAT(
  x,
  path,
  data_var = "data",
  include_metadata = TRUE,
  eeglab = FALSE,
  assay_name = NULL
)
```

## Arguments

- x:

  A PhysioExperiment object.

- path:

  Output file path.

- data_var:

  Name for the data variable in the .mat file.

- include_metadata:

  Logical. If TRUE, includes metadata variables.

- eeglab:

  Logical. If TRUE, exports in EEGLAB-compatible structure.

- assay_name:

  Assay to export. If NULL, uses default assay.

## Value

Invisible NULL.

## References

MathWorks (2024). "MAT-File Format." Technical documentation.
<https://www.mathworks.com/help/matlab/import_export/mat-file-versions.html>

## See also

[`readMAT`](https://x-biosignal.github.io/PhysioIO/reference/readMAT.md),
[`writeCSV`](https://x-biosignal.github.io/PhysioIO/reference/writeCSV.md),
[`writeEDF`](https://x-biosignal.github.io/PhysioIO/reference/writeEDF.md),
[`writePhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/writePhysioHDF5.md)

## Examples

``` r
# 'R.matlab' is an optional dependency; guard the example so it only runs
# when the package is installed.
if (requireNamespace("R.matlab", quietly = TRUE)) {
  pe <- PhysioExperiment(
    assays = list(raw = matrix(0, nrow = 100, ncol = 10)),
    colData = S4Vectors::DataFrame(label = paste0("Ch", seq_len(10))),
    samplingRate = 256
  )
  tf <- tempfile(fileext = ".mat")
  writeMAT(pe, tf)
  unlink(tf)
}
```
