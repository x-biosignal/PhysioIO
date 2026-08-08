# Write PhysioExperiment to BIDS format

Writes data in BIDS-compliant directory structure.

## Usage

``` r
writeBIDS(
  x,
  bids_root,
  subject,
  session = NULL,
  task,
  run = NULL,
  modality = c("eeg", "ieeg"),
  overwrite = FALSE
)
```

## Arguments

- x:

  A PhysioExperiment object.

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

- overwrite:

  If TRUE, overwrites existing files.

## Value

Invisible path to the created files.

## References

Gorgolewski KJ, et al. (2016). "The brain imaging data structure, a
format for organizing and describing outputs of neuroimaging
experiments." Scientific Data, 3, 160044. doi:10.1038/sdata.2016.44

## See also

[`readBIDS`](https://x-biosignal.github.io/PhysioIO/reference/readBIDS.md),
[`writeEDF`](https://x-biosignal.github.io/PhysioIO/reference/writeEDF.md),
[`listBIDSSubjects`](https://x-biosignal.github.io/PhysioIO/reference/listBIDSSubjects.md),
[`validateBIDS`](https://x-biosignal.github.io/PhysioIO/reference/validateBIDS.md)

## Examples

``` r
# Create a PhysioExperiment
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
  colData = S4Vectors::DataFrame(label = paste0("Ch", 1:10)),
  samplingRate = 100
)

# Export to a BIDS dataset in a temporary directory
bids_root <- file.path(tempdir(), "bids-write-demo")
writeBIDS(pe, bids_root, subject = "01", task = "rest")

unlink(bids_root, recursive = TRUE)
```
