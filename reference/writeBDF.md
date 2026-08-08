# Write BDF (BioSemi Data Format) file

Writes a PhysioExperiment object to BDF format (24-bit resolution).

## Usage

``` r
writeBDF(x, path, patient_id = "X", recording_id = "X")
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

Invisible NULL.

## Details

BDF is a 24-bit extension of EDF providing higher resolution than the
standard 16-bit EDF format. It is commonly used with BioSemi acquisition
systems but can be used for any high-resolution physiological data.

## Examples

``` r
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
  colData = S4Vectors::DataFrame(label = paste0("Ch", 1:10)),
  samplingRate = 100
)
tmp <- tempfile(fileext = ".bdf")
writeBDF(pe, tmp)
unlink(tmp)
```
