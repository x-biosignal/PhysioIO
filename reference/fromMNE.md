# Convert an MNE-Python Raw object to a PhysioExperiment

Inverse of
[`toMNE()`](https://x-biosignal.github.io/PhysioIO/reference/toMNE.md):
reads the signal matrix, channel names/types, sampling rate, electrode
montage and annotations from an MNE `Raw` object into a
`PhysioExperiment`. The import is recorded in the object's provenance.

## Usage

``` r
fromMNE(raw)
```

## Arguments

- raw:

  An MNE `Raw` object (e.g. from
  [`toMNE()`](https://x-biosignal.github.io/PhysioIO/reference/toMNE.md)
  or `mne.io.read_raw_*`).

## Value

A `PhysioExperiment` with the signal in the `"raw"` assay.

## See also

[`toMNE()`](https://x-biosignal.github.io/PhysioIO/reference/toMNE.md),
[`hasMNE()`](https://x-biosignal.github.io/PhysioIO/reference/hasMNE.md)

## Examples

``` r
if (hasMNE()) {
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(300), 100, 3)),
    colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz"),
                                   type = rep("eeg", 3)),
    samplingRate = 100)
  pe2 <- fromMNE(toMNE(pe))
}
#> Downloading uv...
#> Done!
```
