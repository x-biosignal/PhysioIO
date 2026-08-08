# Serialize a provenance trail to a W3C PROV interchange file

Writes the provenance / audit trail of a `PhysioExperiment` (or a
provenance `data.frame` from
[`provenance`](https://x-biosignal.r-universe.dev/PhysioCore/reference/provenance.html))
to a W3C PROV document. Three interchange syntaxes are supported:
PROV-JSON (default), PROV in JSON-LD, and PROV-N. The document
round-trips exactly through
[`readProv`](https://x-biosignal.github.io/PhysioIO/reference/readProv.md).

## Usage

``` r
writeProv(x, path, format = c("prov-json", "json-ld", "prov-n"))
```

## Arguments

- x:

  A `PhysioExperiment` or a provenance `data.frame`.

- path:

  Output file path.

- format:

  One of `"prov-json"`, `"json-ld"`, `"prov-n"`.

## Value

`path`, invisibly.

## References

W3C PROV-JSON (Huynh et al. 2013); PROV-O; PROV-N.

## See also

[`readProv`](https://x-biosignal.github.io/PhysioIO/reference/readProv.md),
[`provenance`](https://x-biosignal.r-universe.dev/PhysioCore/reference/provenance.html)

## Examples

``` r
pe <- PhysioExperiment(
  S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)), samplingRate = 100)
pe <- logStep(pe, "filterSignals", params = list(low = 1, high = 40))
tf <- tempfile(fileext = ".json")
writeProv(pe, tf)
readProv(tf)$activity
#> [1] "filterSignals"
```
