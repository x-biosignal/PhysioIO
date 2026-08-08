# List subjects in a BIDS dataset

List subjects in a BIDS dataset

## Usage

``` r
listBIDSSubjects(bids_root)
```

## Arguments

- bids_root:

  Path to the BIDS dataset root.

## Value

Character vector of subject IDs (without 'sub-' prefix).

## References

Gorgolewski KJ, et al. (2016). "The brain imaging data structure, a
format for organizing and describing outputs of neuroimaging
experiments." Scientific Data, 3, 160044. doi:10.1038/sdata.2016.44

## See also

[`listBIDSSessions`](https://x-biosignal.github.io/PhysioIO/reference/listBIDSSessions.md),
[`readBIDS`](https://x-biosignal.github.io/PhysioIO/reference/readBIDS.md),
[`validateBIDS`](https://x-biosignal.github.io/PhysioIO/reference/validateBIDS.md)

## Examples

``` r
# Write a minimal BIDS dataset, then list its subjects
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
  colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
  samplingRate = 100
)
bids_root <- file.path(tempdir(), "bids-list-demo")
writeBIDS(pe, bids_root, subject = "01", task = "rest")

listBIDSSubjects(bids_root)
#> [1] "01"
unlink(bids_root, recursive = TRUE)
```
