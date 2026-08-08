# Convert a PhysioExperiment to an MNE-Python RawArray

Builds an `mne.io.RawArray` from a `PhysioExperiment`: channel names,
channel types and sampling rate populate the `mne.Info`; any electrode
positions
([`getElectrodePositions()`](https://x-biosignal.r-universe.dev/PhysioCore/reference/getElectrodePositions.html))
become a `DigMontage`; and any events
([`getEvents()`](https://x-biosignal.r-universe.dev/PhysioCore/reference/getEvents.html))
become `mne.Annotations`. The signal matrix is passed through unchanged,
so `fromMNE(toMNE(x))` reproduces it exactly.

## Usage

``` r
toMNE(x, assay = NULL)
```

## Arguments

- x:

  A `PhysioExperiment`.

- assay:

  Assay to export (default: the object's default assay).

## Value

An `mne.io.RawArray` Python object.

## Details

Channel types not recognised by MNE are mapped to `"misc"` (and are
lower-cased to MNE's convention). Channel names must be unique. An
event's `type` and (when present) `value` are packed into the annotation
description so both survive the round-trip; a missing (`NA`) value
becomes `""` because MNE annotations cannot represent `NA`. Events whose
onset falls outside the recording are dropped by MNE (with a warning).

## References

Gramfort A, et al. (2013). "MEG and EEG data analysis with MNE-Python."
Frontiers in Neuroscience, 7, 267.

## See also

[`fromMNE()`](https://x-biosignal.github.io/PhysioIO/reference/fromMNE.md),
[`hasMNE()`](https://x-biosignal.github.io/PhysioIO/reference/hasMNE.md)

## Examples

``` r
if (hasMNE()) {
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(300), 100, 3)),
    colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz"),
                                   type = rep("eeg", 3)),
    samplingRate = 100)
  raw <- toMNE(pe)
}
```
