# Read a WFDB record

Reads a WFDB record's header (`.hea`) and interleaved signal file
(`.dat`) into a `PhysioExperiment`. Storage formats 16, 61, 80, 212, 24
and 32 are supported.

## Usage

``` r
readWFDB(record)
```

## Arguments

- record:

  Path to the record with or without extension (e.g. `"path/to/100"` or
  `"path/to/100.hea"`).

## Value

A `PhysioExperiment` with physical signal values in the `"raw"` assay,
channel labels/units/gain in `colData`, and the sampling rate set.

## References

Moody, G. B. & Mark, R. G. (2001). The impact of the MIT-BIH Arrhythmia
Database. *IEEE Eng. Med. Biol.*, 20(3), 45-50.

## See also

[`writeWFDB`](https://x-biosignal.github.io/PhysioIO/reference/writeWFDB.md),
[`readWFDBAnnotation`](https://x-biosignal.github.io/PhysioIO/reference/readWFDBAnnotation.md)
