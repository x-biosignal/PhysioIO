# GDF (General Data Format) File I/O for PhysioExperiment

Functions for reading and writing GDF format files. GDF is designed to
overcome limitations of EDF and is commonly used in BCI research.
Supports GDF version 1.x and 2.x. Read PhysioExperiment from GDF file

## Usage

``` r
readGDF(path, channels = NULL, start_time = NULL, end_time = NULL)
```

## Arguments

- path:

  Path to the GDF file.

- channels:

  Optional integer vector of channel indices or character vector of
  channel names to load. If NULL, loads all channels.

- start_time:

  Optional start time in seconds for selective loading.

- end_time:

  Optional end time in seconds for selective loading.

## Value

A PhysioExperiment object.

## Details

Reads physiological signal data from a GDF (General Data Format) file.
GDF is an extension of EDF with improved features including better event
support, more data types, and subject information.

## Examples

``` r
# Round-trip a small recording through a temporary GDF file
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(300), nrow = 100, ncol = 3)),
  colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz")),
  samplingRate = 100
)
tmp <- tempfile(fileext = ".gdf")
writeGDF(pe, tmp)

pe_in <- readGDF(tmp)
pe_sub <- readGDF(tmp, channels = c("Fz", "Cz"))
unlink(tmp)
```
