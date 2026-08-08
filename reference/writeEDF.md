# Write EDF file

Writes a PhysioExperiment object to EDF format.

## Usage

``` r
writeEDF(x, path, patient_id = "X", recording_id = "X")
```

## Arguments

- x:

  A PhysioExperiment object.

- path:

  Output file path.

- patient_id:

  Patient identification string.

- recording_id:

  Recording identification string.

## Value

Invisible `NULL`. The EDF file is written to `path` as a side effect.

## References

Kemp, B., et al. (1992). "A simple format for exchange of digitized
polygraphic recordings." Electroencephalography and Clinical
Neurophysiology, 82(5), 391-393. doi:10.1016/0013-4694(92)90009-7

## See also

[`readEDF`](https://x-biosignal.github.io/PhysioIO/reference/readEDF.md),
[`writeBIDS`](https://x-biosignal.github.io/PhysioIO/reference/writeBIDS.md),
[`writePhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/writePhysioHDF5.md),
[`writeCSV`](https://x-biosignal.github.io/PhysioIO/reference/writeCSV.md)

## Examples

``` r
# Create a PhysioExperiment with EEG-like data
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
  colData = S4Vectors::DataFrame(label = paste0("Ch", 1:10)),
  samplingRate = 100
)

# Export to EDF format in a temporary file
tmp <- tempfile(fileext = ".edf")
writeEDF(pe, tmp, patient_id = "Subject01", recording_id = "Session1")

unlink(tmp)
```
