# Read the BioSemi Status channel of a BDF file

Returns the raw digital values of the `"Status"` channel. The low 16
bits of each value are the stimulus trigger inputs.

## Usage

``` r
readBDFStatus(path)
```

## Arguments

- path:

  Path to a BDF file.

## Value

A list with `values` (integer status words) and `fs` (the Status channel
sampling rate), or `NULL` if the file has no Status channel.

## See also

[`bdfTriggerEvents`](https://x-biosignal.github.io/PhysioIO/reference/bdfTriggerEvents.md),
[`readBDF`](https://x-biosignal.github.io/PhysioIO/reference/readBDF.md)
