# Write a BIDS derivative recording

Writes `x` as a derivative under `deriv_root` with a `desc-<label>`
entity, and a derivative `dataset_description.json` whose `GeneratedBy`
is populated from the object's provenance
([`provenance`](https://x-biosignal.r-universe.dev/PhysioCore/reference/provenance.html)).
The signals are stored as a gzipped `_physio.tsv.gz` plus JSON.

## Usage

``` r
writeBIDSDerivative(
  x,
  deriv_root,
  subject,
  task,
  desc,
  session = NULL,
  run = NULL,
  pipeline_name = NULL,
  overwrite = FALSE
)
```

## Arguments

- x:

  A `PhysioExperiment` (typically a processed derivative).

- deriv_root:

  Derivative dataset root (e.g. `"<bids>/derivatives/physio-clean"`).

- subject, task, session, run:

  BIDS entities.

- desc:

  The `desc-` label (e.g. `"clean"`).

- pipeline_name:

  Name recorded in `GeneratedBy` (default `basename(deriv_root)`).

- overwrite:

  Overwrite existing files (default `FALSE`).

## Value

The written data path, invisibly.

## See also

[`readBIDSDerivatives`](https://x-biosignal.github.io/PhysioIO/reference/readBIDSDerivatives.md)
