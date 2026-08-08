# Write a WFDB record

Writes a `PhysioExperiment` to a WFDB record (`.hea` + `.dat`).

## Usage

``` r
writeWFDB(x, record, format = 16L, gain = 200, baseline = 0)
```

## Arguments

- x:

  A `PhysioExperiment` (2D `"raw"` assay of physical values).

- record:

  Output record path (without extension).

- format:

  WFDB storage format: one of 16, 61, 80, 212, 24, 32.

- gain:

  ADC gain (units per ADU); a scalar or one per channel.

- baseline:

  ADC baseline value (raw value for 0 physical); scalar or per channel.

## Value

`record`, invisibly.

## See also

[`readWFDB`](https://x-biosignal.github.io/PhysioIO/reference/readWFDB.md)
