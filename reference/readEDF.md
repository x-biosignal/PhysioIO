# EDF/EDF+ file I/O

Functions for reading European Data Format (EDF/EDF+) files commonly
used for EEG, PSG, and other physiological recordings. Read EDF/EDF+
file

## Usage

``` r
readEDF(
  path,
  channels = NULL,
  start_time = NULL,
  end_time = NULL,
  resample = FALSE
)
```

## Arguments

- path:

  Path to the EDF file.

- channels:

  Optional character vector of channel names to load. If NULL, all
  channels are loaded.

- start_time:

  Optional start time in seconds for reading a subset.

- end_time:

  Optional end time in seconds for reading a subset.

- resample:

  Logical. If `FALSE` (default) and channels have differing native
  sampling rates, the native rates are preserved by returning a
  `MultiRatePhysioExperiment` (one stream per rate). If `TRUE`, all
  channels are resampled to the highest rate and a single
  `PhysioExperiment` is returned (legacy behaviour).

## Value

A
[`PhysioExperiment`](https://x-biosignal.r-universe.dev/PhysioCore/reference/PhysioExperiment-class.html)
with the EDF signal data in the `"raw"` assay, or - when channels have
differing native rates and `resample = FALSE` - a
[`MultiRatePhysioExperiment`](https://x-biosignal.r-universe.dev/PhysioCore/reference/MultiRatePhysioExperiment.html).
Channel metadata (label, transducer, physical dimensions,
digital/physical min/max) are stored in `colData`, and recording
metadata in `metadata`.

## Details

Reads an EDF or EDF+ file and returns a PhysioExperiment object.

EDF (European Data Format) is a standard file format for storing
multichannel physiological signals. EDF+ extends this with annotations
and discontinuous recordings.

The function parses the EDF header to extract:

- Channel labels and types

- Sampling rates (may differ per channel)

- Physical dimensions (units)

- Recording start date/time

If channels have different native sampling rates, the rates are
preserved by returning a `MultiRatePhysioExperiment` (one stream per
rate); pass `resample = TRUE` for the legacy single-rate behaviour.

## References

Kemp, B., et al. (1992). "A simple format for exchange of digitized
polygraphic recordings." Electroencephalography and Clinical
Neurophysiology, 82(5), 391-393. doi:10.1016/0013-4694(92)90009-7

## See also

[`writeEDF`](https://x-biosignal.github.io/PhysioIO/reference/writeEDF.md),
[`readBIDS`](https://x-biosignal.github.io/PhysioIO/reference/readBIDS.md),
[`readPhysioHDF5`](https://x-biosignal.github.io/PhysioIO/reference/readPhysioHDF5.md),
[`readCSV`](https://x-biosignal.github.io/PhysioIO/reference/readCSV.md)

## Examples

``` r
# Round-trip a small recording through a temporary EDF file
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
  colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "C3", "C4")),
  samplingRate = 100
)
tmp <- tempfile(fileext = ".edf")
writeEDF(pe, tmp)

# Read the whole file back
pe_in <- readEDF(tmp)
dim(SummarizedExperiment::assay(pe_in, "raw"))
#> [1] 100   4

# Read only specific channels
pe_sub <- readEDF(tmp, channels = c("Fp1", "C3"))

unlink(tmp)
```
