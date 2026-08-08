# Write PhysioExperiment to BrainVision format

Saves a PhysioExperiment object to BrainVision format (three files:
.vhdr header, .vmrk markers, .eeg binary data).

## Usage

``` r
writeBrainVision(
  x,
  path,
  overwrite = FALSE,
  binary_format = c("IEEE_FLOAT_32", "INT_16", "INT_32"),
  assay_name = NULL
)
```

## Arguments

- x:

  A PhysioExperiment object.

- path:

  Output path (without extension, or with .vhdr extension).

- overwrite:

  Logical. If TRUE, overwrites existing files.

- binary_format:

  Binary format for data: "IEEE_FLOAT_32" (default), "INT_16", or
  "INT_32".

- assay_name:

  Assay to export. If NULL, uses default assay.

## Value

Invisible NULL.

## Examples

``` r
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
  colData = S4Vectors::DataFrame(label = paste0("Ch", 1:10)),
  samplingRate = 100
)
base <- tempfile()
writeBrainVision(pe, base)
unlink(paste0(base, c(".vhdr", ".vmrk", ".eeg")))
```
