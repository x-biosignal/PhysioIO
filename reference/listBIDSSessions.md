# List sessions for a subject in BIDS dataset

List sessions for a subject in BIDS dataset

## Usage

``` r
listBIDSSessions(bids_root, subject)
```

## Arguments

- bids_root:

  Path to the BIDS dataset root.

- subject:

  Subject identifier (without 'sub-' prefix).

## Value

Character vector of session IDs (without 'ses-' prefix).

## References

Gorgolewski KJ, et al. (2016). "The brain imaging data structure, a
format for organizing and describing outputs of neuroimaging
experiments." Scientific Data, 3, 160044. doi:10.1038/sdata.2016.44

## See also

[`listBIDSSubjects`](https://x-biosignal.github.io/PhysioIO/reference/listBIDSSubjects.md),
[`readBIDS`](https://x-biosignal.github.io/PhysioIO/reference/readBIDS.md),
[`validateBIDS`](https://x-biosignal.github.io/PhysioIO/reference/validateBIDS.md)

## Examples

``` r
# Write a BIDS dataset with a session, then list sessions for the subject
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
  colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
  samplingRate = 100
)
bids_root <- file.path(tempdir(), "bids-session-demo")
writeBIDS(pe, bids_root, subject = "01", session = "baseline", task = "rest")

listBIDSSessions(bids_root, subject = "01")
#> [1] "baseline"
unlink(bids_root, recursive = TRUE)
```
