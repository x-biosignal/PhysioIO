# Write a BIDS continuous physiological recording

Writes a gzipped `_physio.tsv.gz` (headerless, columns defined in the
JSON) plus a `_physio.json` sidecar with `SamplingFrequency`,
`StartTime` and `Columns`.

## Usage

``` r
writeBIDSPhysio(
  x,
  bids_root,
  subject,
  task,
  session = NULL,
  run = NULL,
  start_time = 0,
  overwrite = FALSE
)
```

## Arguments

- x:

  A `PhysioExperiment` (2D assay).

- bids_root, subject, task, session, run:

  BIDS entities.

- start_time:

  Recording start time relative to the main recording, in seconds (BIDS
  `StartTime`; default 0).

- overwrite:

  Overwrite existing files (default `FALSE`).

## Value

The written `.tsv.gz` path, invisibly.

## See also

[`readBIDSPhysio`](https://x-biosignal.github.io/PhysioIO/reference/readBIDSPhysio.md),
[`attachBIDSPhysio`](https://x-biosignal.github.io/PhysioIO/reference/attachBIDSPhysio.md)
