# Read BDF (BioSemi Data Format) file

Reads a BDF file and returns a PhysioExperiment object. BDF is a 24-bit
extension of the EDF format used by BioSemi systems.

## Usage

``` r
readBDF(
  path,
  channels = NULL,
  start_time = NULL,
  end_time = NULL,
  resample = FALSE,
  status = TRUE
)
```

## Arguments

- path:

  Path to the BDF file.

- channels:

  Optional character vector of channel names to load. If NULL, all
  channels are loaded.

- start_time:

  Optional start time in seconds for reading a subset. Note that BDF
  subsetting is record-granular: `start_time`/`end_time` are rounded
  outward to whole data records (typically 1 s), so the returned signal
  and any extracted trigger onsets share that record-aligned window
  (onsets are relative to it and may extend slightly past `end_time`).

- end_time:

  Optional end time in seconds for reading a subset.

- resample:

  Logical. If `FALSE` (default) and channels have differing native
  rates, a `MultiRatePhysioExperiment` is returned; if `TRUE`, all
  channels are resampled to the highest rate (legacy).

- status:

  Logical. If `TRUE` (default) and a BioSemi `"Status"` channel is
  present, stimulus triggers are extracted from it (see
  [`bdfTriggerEvents`](https://x-biosignal.github.io/PhysioIO/reference/bdfTriggerEvents.md))
  and attached to the result as events.

## Value

A `PhysioExperiment`, or a
[`MultiRatePhysioExperiment`](https://x-biosignal.r-universe.dev/PhysioCore/reference/MultiRatePhysioExperiment.html)
when native rates differ and `resample = FALSE`.

## Details

BDF (BioSemi Data Format) is a 24-bit variant of EDF used by BioSemi
acquisition systems. The main differences from EDF are:

- 24-bit data resolution (vs 16-bit in EDF)

- Header starts with 0xFF followed by "BIOSEMI"

- Digital range is -8388608 to 8388607

## Examples

``` r
# Round-trip a small recording through a temporary BDF file
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
  colData = S4Vectors::DataFrame(label = c("A1", "A2", "B1", "B2")),
  samplingRate = 100
)
tmp <- tempfile(fileext = ".bdf")
writeBDF(pe, tmp)

# Read the file back
pe_in <- readBDF(tmp)

# Read only specific channels
pe_sub <- readBDF(tmp, channels = c("A1", "B1"))

unlink(tmp)
```
