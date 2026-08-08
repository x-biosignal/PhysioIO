# BrainVision File Format I/O for PhysioExperiment

Functions for reading and writing BrainVision format files
(.vhdr/.vmrk/.eeg). BrainVision is one of the official BIDS-EEG formats
and is widely supported by EEG analysis software (MNE-Python, EEGLAB,
FieldTrip, etc.). Read PhysioExperiment from BrainVision files

## Usage

``` r
readBrainVision(path, channels = NULL)
```

## Arguments

- path:

  Path to the .vhdr header file.

- channels:

  Optional character vector of channel names to load. If NULL, loads all
  channels.

## Value

A PhysioExperiment object.

## Details

Reads EEG data from BrainVision format files. The format consists of
three files: a header file (.vhdr), a marker file (.vmrk), and a binary
data file (.eeg).

## Examples

``` r
# Round-trip a small recording through temporary BrainVision files
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
  colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
  samplingRate = 100
)
base <- tempfile()
writeBrainVision(pe, base)

pe_in <- readBrainVision(paste0(base, ".vhdr"))
dim(SummarizedExperiment::assay(pe_in, "raw"))
#> [1] 100   4

unlink(paste0(base, c(".vhdr", ".vmrk", ".eeg")))
```
