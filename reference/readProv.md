# Read a W3C PROV interchange file back into a provenance table

Inverse of
[`writeProv`](https://x-biosignal.github.io/PhysioIO/reference/writeProv.md).
The format is auto-detected from the file contents (PROV-N text, PROV
JSON-LD, or PROV-JSON).

## Usage

``` r
readProv(path)
```

## Arguments

- path:

  Path to a PROV document written by
  [`writeProv`](https://x-biosignal.github.io/PhysioIO/reference/writeProv.md).

## Value

A provenance `data.frame` with the same columns as
[`provenance`](https://x-biosignal.r-universe.dev/PhysioCore/reference/provenance.html).

## See also

[`writeProv`](https://x-biosignal.github.io/PhysioIO/reference/writeProv.md)

## Examples

``` r
pe <- PhysioExperiment(
  S4Vectors::SimpleList(raw = matrix(rnorm(20), 10, 2)), samplingRate = 100)
pe <- logStep(pe, "import")
tf <- tempfile(fileext = ".json")
writeProv(pe, tf)
readProv(tf)
#>     step activity                            entity used generated
#> 1 import   import pe:import@2026-08-10T02:59:24.947 <NA>      <NA>
#>                  agent   user package version       startedAtTime
#> 1 runner@runnervmvrwv9 runner    <NA>    <NA> 2026-08-10 02:59:24
#>           endedAtTime           timestamp params params_json
#> 1 2026-08-10 02:59:24 2026-08-10 02:59:24                 {}
```
