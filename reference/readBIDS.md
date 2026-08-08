# BIDS Format Support for PhysioExperiment

Functions for reading and writing data in BIDS (Brain Imaging Data
Structure) format. Supports BIDS-EEG and BIDS-iEEG specifications. Read
PhysioExperiment from BIDS dataset

## Usage

``` r
readBIDS(
  bids_root,
  subject,
  session = NULL,
  task,
  run = NULL,
  modality = c("eeg", "ieeg"),
  load_events = TRUE
)
```

## Arguments

- bids_root:

  Path to the BIDS dataset root directory.

- subject:

  Subject identifier (without 'sub-' prefix).

- session:

  Session identifier (without 'ses-' prefix). Optional.

- task:

  Task name.

- run:

  Run number. Optional.

- modality:

  Data modality: "eeg" or "ieeg".

- load_events:

  If TRUE, loads events from the events.tsv file.

## Value

A PhysioExperiment object.

## Details

Reads EEG/iEEG data from a BIDS-compliant directory structure.

## References

Gorgolewski KJ, et al. (2016). "The brain imaging data structure, a
format for organizing and describing outputs of neuroimaging
experiments." Scientific Data, 3, 160044. doi:10.1038/sdata.2016.44

## See also

[`writeBIDS`](https://x-biosignal.github.io/PhysioIO/reference/writeBIDS.md),
[`validateBIDS`](https://x-biosignal.github.io/PhysioIO/reference/validateBIDS.md),
[`readEDF`](https://x-biosignal.github.io/PhysioIO/reference/readEDF.md),
[`listBIDSSubjects`](https://x-biosignal.github.io/PhysioIO/reference/listBIDSSubjects.md)

## Examples

``` r
# Write a minimal BIDS dataset to a temporary directory, then read it back
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
  colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
  samplingRate = 100
)
bids_root <- file.path(tempdir(), "bids-demo")
writeBIDS(pe, bids_root, subject = "01", task = "rest")

# Read EEG data back from the BIDS dataset
pe_in <- readBIDS(bids_root, subject = "01", task = "rest")
dim(SummarizedExperiment::assay(pe_in, "raw"))
#> [1] 100   4

unlink(bids_root, recursive = TRUE)
```
