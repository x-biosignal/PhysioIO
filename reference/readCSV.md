# CSV/TSV I/O for PhysioExperiment

Functions for reading and writing signal data in CSV/TSV format.
Supports both wide format (time x channels) and long format. Read
PhysioExperiment from CSV file

## Usage

``` r
readCSV(
  path,
  format = c("wide", "long"),
  time_col = NULL,
  channel_cols = NULL,
  sampling_rate = NULL,
  sep = ",",
  header = TRUE,
  ...
)
```

## Arguments

- path:

  Path to the CSV file.

- format:

  Data format: "wide" (time x channels) or "long" (stacked).

- time_col:

  Name of the time column. If NULL, assumes first column or generates
  time from sampling rate.

- channel_cols:

  For wide format, column names/indices to use as channels. If NULL,
  uses all non-time columns.

- sampling_rate:

  Sampling rate in Hz. Required if time column is not present.

- sep:

  Column separator. Default is ",".

- header:

  Logical. If TRUE, first row contains column names.

- ...:

  Additional arguments passed to read.csv/read.table.

## Value

A PhysioExperiment object.

## Details

Reads physiological signal data from a CSV file.

## References

Wickham H (2014). "Tidy Data." Journal of Statistical Software, 59(10),
1-23. doi:10.18637/jss.v059.i10

## See also

[`writeCSV`](https://x-biosignal.github.io/PhysioIO/reference/writeCSV.md),
[`readEventsCSV`](https://x-biosignal.github.io/PhysioIO/reference/readEventsCSV.md),
[`readEDF`](https://x-biosignal.github.io/PhysioIO/reference/readEDF.md),
[`readMAT`](https://x-biosignal.github.io/PhysioIO/reference/readMAT.md)

## Examples

``` r
# Write a wide-format CSV, then read it back
pe <- PhysioExperiment(
  assays = list(raw = matrix(rnorm(400), nrow = 100, ncol = 4)),
  colData = S4Vectors::DataFrame(label = c("Fz", "Cz", "Pz", "Oz")),
  samplingRate = 100
)
tmp <- tempfile(fileext = ".csv")
writeCSV(pe, tmp)

# Read using the written time column
pe_in <- readCSV(tmp, time_col = "time")

# Read without a time column (generate time from sampling rate)
pe_sr <- readCSV(tmp, channel_cols = c("Fz", "Cz", "Pz", "Oz"),
                 sampling_rate = 100)

unlink(tmp)
```
