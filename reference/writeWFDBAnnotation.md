# Write a WFDB annotation file

Writes a `PhysioEvents` object (onset in samples, `type` = beat symbol,
`value` = auxiliary string) to a WFDB binary annotation file.

## Usage

``` r
writeWFDBAnnotation(events, path)
```

## Arguments

- events:

  A `PhysioEvents` object with onsets in samples.

- path:

  Output annotation file path.

## Value

`path`, invisibly.

## See also

[`readWFDBAnnotation`](https://x-biosignal.github.io/PhysioIO/reference/readWFDBAnnotation.md)
