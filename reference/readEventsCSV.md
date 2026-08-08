# Read events from CSV/TSV file

Reads event markers from a CSV file with onset, duration, and type
columns.

## Usage

``` r
readEventsCSV(
  path,
  onset_col = "onset",
  duration_col = "duration",
  type_col = "type",
  value_col = "value",
  sep = ",",
  ...
)
```

## Arguments

- path:

  Path to the CSV file.

- onset_col:

  Name of the onset column (in seconds).

- duration_col:

  Name of the duration column.

- type_col:

  Name of the event type column.

- value_col:

  Name of the event value column.

- sep:

  Column separator.

- ...:

  Additional arguments passed to read.csv.

## Value

A PhysioEvents object.

## References

Wickham H (2014). "Tidy Data." Journal of Statistical Software, 59(10),
1-23. doi:10.18637/jss.v059.i10

## See also

[`writeEventsCSV`](https://x-biosignal.github.io/PhysioIO/reference/writeEventsCSV.md),
[`readCSV`](https://x-biosignal.github.io/PhysioIO/reference/readCSV.md),
[`readBIDS`](https://x-biosignal.github.io/PhysioIO/reference/readBIDS.md)

## Examples

``` r
# Write events to a temporary CSV, then read them back
events <- PhysioEvents(
  onset = c(1.0, 2.5, 4.0),
  duration = c(0.5, 0.5, 0.5),
  type = c("stimulus", "stimulus", "response"),
  value = c("A", "B", "correct")
)
tmp <- tempfile(fileext = ".csv")
writeEventsCSV(events, tmp)

events_in <- readEventsCSV(tmp)
unlink(tmp)
```
