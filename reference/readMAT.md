# Read PhysioExperiment from MATLAB .mat file

Reads physiological signal data from a MATLAB .mat file. Supports both
standard .mat files and EEGLAB .set structures.

## Usage

``` r
readMAT(
  path,
  data_var = NULL,
  sr_var = NULL,
  channel_var = NULL,
  event_var = NULL,
  transpose = FALSE
)
```

## Arguments

- path:

  Path to the .mat file.

- data_var:

  Name of the variable containing signal data. If NULL, attempts to
  auto-detect.

- sr_var:

  Name of the variable containing sampling rate.

- channel_var:

  Name of the variable containing channel labels.

- event_var:

  Name of the variable containing events.

- transpose:

  Logical. If TRUE, transposes the data matrix.

## Value

A PhysioExperiment object.

## Details

The function attempts to auto-detect the data structure if variable
names are not specified. It looks for common variable names used in EEG
toolboxes:

- data, EEG.data, signal, X for signal data

- srate, fs, Fs, samplingRate for sampling rate

- chanlocs, channels, labels for channel information

- event, events, EEG.event for events

## References

MathWorks (2024). "MAT-File Format." Technical documentation.
<https://www.mathworks.com/help/matlab/import_export/mat-file-versions.html>

## See also

[`writeMAT`](https://x-biosignal.github.io/PhysioIO/reference/writeMAT.md),
[`readEDF`](https://x-biosignal.github.io/PhysioIO/reference/readEDF.md),
[`readCSV`](https://x-biosignal.github.io/PhysioIO/reference/readCSV.md),
[`readPhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/readPhysioHDF5.md)

## Examples

``` r
# 'R.matlab' is an optional dependency; guard the round-trip example so it
# only runs when the package is installed.
if (requireNamespace("R.matlab", quietly = TRUE)) {
  pe <- PhysioExperiment(
    assays = list(raw = matrix(0, nrow = 100, ncol = 3)),
    colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz")),
    samplingRate = 256
  )
  tf <- tempfile(fileext = ".mat")
  writeMAT(pe, tf)
  pe2 <- readMAT(tf)
  unlink(tf)
}
```
