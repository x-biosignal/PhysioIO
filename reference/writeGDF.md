# Write PhysioExperiment to GDF format

Saves a PhysioExperiment object to GDF (General Data Format) version
2.x.

## Usage

``` r
writeGDF(
  x,
  path,
  patient_id = "",
  recording_id = "",
  overwrite = FALSE,
  assay_name = NULL
)
```

## Arguments

- x:

  A PhysioExperiment object.

- path:

  Output file path.

- patient_id:

  Patient identifier string.

- recording_id:

  Recording identifier string.

- overwrite:

  Logical. If TRUE, overwrites existing file.

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
tmp <- tempfile(fileext = ".gdf")
writeGDF(pe, tmp)
unlink(tmp)
```
