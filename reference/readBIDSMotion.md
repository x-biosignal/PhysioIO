# Read a Motion-BIDS recording

Read a Motion-BIDS recording

## Usage

``` r
readBIDSMotion(
  bids_root,
  subject,
  task,
  session = NULL,
  run = NULL,
  tracking_system = NULL
)
```

## Arguments

- bids_root:

  BIDS dataset root.

- subject, task:

  Subject and task labels.

- session, run:

  Optional session label and run number.

- tracking_system:

  Optional tracking-system label to disambiguate.

## Value

A `PhysioExperiment` with the motion data, `colData` carrying
`tracked_point`/`component`/units, and the sampling rate.

## See also

[`writeBIDSMotion`](https://x-biosignal.github.io/PhysioIO/reference/writeBIDSMotion.md)
