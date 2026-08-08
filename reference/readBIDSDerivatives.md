# Read the derivative recordings of a subject

Read the derivative recordings of a subject

## Usage

``` r
readBIDSDerivatives(deriv_root, subject, session = NULL)
```

## Arguments

- deriv_root:

  Derivative dataset root.

- subject:

  Subject label.

- session:

  Optional session label.

## Value

A named list of `PhysioExperiment` objects, one per `desc-<label>`
derivative found for the subject.

## See also

[`writeBIDSDerivative`](https://x-biosignal.github.io/PhysioIO/reference/writeBIDSDerivative.md)
