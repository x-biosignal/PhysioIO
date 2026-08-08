# Validate BIDS dataset structure

Performs basic validation of BIDS compliance.

## Usage

``` r
validateBIDS(bids_root)
```

## Arguments

- bids_root:

  Path to the BIDS dataset root.

## Value

A list with validation results.

## References

Gorgolewski KJ, et al. (2016). "The brain imaging data structure, a
format for organizing and describing outputs of neuroimaging
experiments." Scientific Data, 3, 160044. doi:10.1038/sdata.2016.44

## See also

[`readBIDS`](https://x-biosignal.github.io/PhysioIO/reference/readBIDS.md),
[`writeBIDS`](https://x-biosignal.github.io/PhysioIO/reference/writeBIDS.md),
[`listBIDSSubjects`](https://x-biosignal.github.io/PhysioIO/reference/listBIDSSubjects.md)

## Examples

``` r
# Write a minimal BIDS dataset, then validate it
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
  colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
  samplingRate = 100
)
bids_root <- file.path(tempdir(), "bids-validate-demo")
writeBIDS(pe, bids_root, subject = "01", task = "rest")

result <- validateBIDS(bids_root)
result$valid
#> [1] TRUE

unlink(bids_root, recursive = TRUE)
```
