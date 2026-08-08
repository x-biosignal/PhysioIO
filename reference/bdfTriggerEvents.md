# Extract trigger events from a BioSemi Status channel

Detects transitions of the low-16-bit trigger value to a new non-zero
code and returns them as a `PhysioEvents`: each rising transition is an
event whose onset is the transition time (seconds) and whose value is
the trigger code.

## Usage

``` r
bdfTriggerEvents(status, sampling_rate)
```

## Arguments

- status:

  Integer vector of raw Status-channel digital values (as from
  [`readBDFStatus`](https://x-biosignal.github.io/PhysioIO/reference/readBDFStatus.md)).

- sampling_rate:

  Sampling rate of the Status channel in Hz.

## Value

A `PhysioEvents` object.

## See also

[`readBDFStatus`](https://x-biosignal.github.io/PhysioIO/reference/readBDFStatus.md),
[`readBDF`](https://x-biosignal.github.io/PhysioIO/reference/readBDF.md)
