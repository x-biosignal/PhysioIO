# Write a Motion-BIDS recording

Writes a motion-capture `PhysioExperiment` in the BIDS `motion` datatype
(Jeung et al. 2023): a headerless `_motion.tsv`, a `_channels.tsv`
carrying `tracked_point`/`component`, and a `_motion.json` sidecar with
`SamplingFrequency` and `TrackingSystemName`.

## Usage

``` r
writeBIDSMotion(
  x,
  bids_root,
  subject,
  task,
  session = NULL,
  run = NULL,
  tracking_system = "unspecified",
  overwrite = FALSE
)
```

## Arguments

- x:

  A `PhysioExperiment` of motion data (2D assay). `colData` columns
  `label`, `type`, `unit`, `tracked_point` and `component` are used when
  present.

- bids_root:

  BIDS dataset root.

- subject, task:

  Subject label and task label.

- session, run:

  Optional session label and run number.

- tracking_system:

  Tracking-system label (the `tracksys-` entity and
  `TrackingSystemName`).

- overwrite:

  Overwrite existing files (default `FALSE`).

## Value

The data directory path, invisibly.

## References

Jeung, S., et al. (2023). Motion-BIDS. *Scientific Data*.

## See also

[`readBIDSMotion`](https://x-biosignal.github.io/PhysioIO/reference/readBIDSMotion.md)
