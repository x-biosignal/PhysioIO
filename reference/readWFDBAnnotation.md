# Read a WFDB annotation file

Parses a WFDB binary annotation file (MIT format) into a `PhysioEvents`:
each annotation's sample number becomes the event `onset` (in samples),
its beat symbol the event `type`, and any auxiliary string the event
`value`.

## Usage

``` r
readWFDBAnnotation(path)
```

## Arguments

- path:

  Path to the annotation file (e.g. `"100.atr"`).

## Value

A `PhysioEvents` object (onset in samples).

## See also

[`writeWFDBAnnotation`](https://x-biosignal.github.io/PhysioIO/reference/writeWFDBAnnotation.md)
