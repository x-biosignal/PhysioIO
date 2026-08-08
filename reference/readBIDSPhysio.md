# Read a BIDS continuous physiological recording

Read a BIDS continuous physiological recording

## Usage

``` r
readBIDSPhysio(path)
```

## Arguments

- path:

  Path to the `_physio.tsv.gz` file (its `_physio.json` sidecar is read
  alongside).

## Value

A `PhysioExperiment` with the physio signals; `StartTime` is stored in
`metadata()$bids_start_time`.

## See also

[`writeBIDSPhysio`](https://x-biosignal.github.io/PhysioIO/reference/writeBIDSPhysio.md),
[`attachBIDSPhysio`](https://x-biosignal.github.io/PhysioIO/reference/attachBIDSPhysio.md)
