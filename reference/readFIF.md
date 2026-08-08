# Read an Elekta/Neuromag/MNE FIF (FIFF) file

Reads a raw FIFF file into a `PhysioExperiment`. The native parser reads
the FIFF tag stream directly (channel info, sampling rate and data
buffers). For files the native path cannot handle, and when the Python
mne module is available through reticulate, it can fall back to
`mne.io.read_raw_fif()`.

## Usage

``` r
readFIF(path, backend = c("auto", "native", "mne"))
```

## Arguments

- path:

  Path to a `.fif` file.

- backend:

  One of `"auto"` (native, then mne on failure), `"native"` (native
  only), or `"mne"` (force the reticulate/mne path).

## Value

A `PhysioExperiment` with calibrated signal values in the `"raw"` assay,
channel labels/types/units in `colData`, and the sampling rate set.

## References

FIFF file format (Elekta Neuromag); MNE-Python read_raw_fif.

## See also

[`readEDF`](https://x-biosignal.github.io/PhysioIO/reference/readEDF.md),
[`readBDF`](https://x-biosignal.github.io/PhysioIO/reference/readBDF.md)
