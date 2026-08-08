# Attach a physio recording to a main recording as an aligned stream

Combines a main recording and a `_physio` recording into a
`MultiRatePhysioExperiment`, using the physio's `StartTime` as its clock
offset. The two keep their own sampling rates.

## Usage

``` r
attachBIDSPhysio(main, physio)
```

## Arguments

- main:

  A `PhysioExperiment` (the primary recording).

- physio:

  A `PhysioExperiment` from
  [`readBIDSPhysio`](https://x-biosignal.github.io/PhysioIO/reference/readBIDSPhysio.md).

## Value

A
[`MultiRatePhysioExperiment`](https://x-biosignal.r-universe.dev/PhysioCore/reference/MultiRatePhysioExperiment.html).

## See also

[`readBIDSPhysio`](https://x-biosignal.github.io/PhysioIO/reference/readBIDSPhysio.md)
