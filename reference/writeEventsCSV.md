# Write events to CSV file

Writes PhysioEvents to a CSV file.

## Usage

``` r
writeEventsCSV(events, path, sep = ",", ...)
```

## Arguments

- events:

  A PhysioEvents object.

- path:

  Output file path.

- sep:

  Column separator.

- ...:

  Additional arguments passed to write.csv.

## Value

Invisible path to the created file.

## References

Wickham H (2014). "Tidy Data." Journal of Statistical Software, 59(10),
1-23. doi:10.18637/jss.v059.i10

## See also

[`readEventsCSV`](https://x-biosignal.github.io/PhysioIO/reference/readEventsCSV.md),
[`writeCSV`](https://x-biosignal.github.io/PhysioIO/reference/writeCSV.md),
[`writeBIDS`](https://x-biosignal.github.io/PhysioIO/reference/writeBIDS.md)

## Examples

``` r
# Create events
events <- PhysioEvents(
  onset = c(1.0, 2.5, 4.0),
  duration = c(0.5, 0.5, 0.5),
  type = c("stimulus", "stimulus", "response"),
  value = c("A", "B", "correct")
)

# Write to temporary file
tmp <- tempfile(fileext = ".csv")
writeEventsCSV(events, tmp)

# Clean up
unlink(tmp)
```
