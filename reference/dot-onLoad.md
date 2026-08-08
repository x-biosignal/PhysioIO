# Package on-load hook

Advertises the readers/writers PhysioIO provides through the PhysioCore
plugin registry (see
[`` PhysioCore::`physio-registry` ``](https://x-biosignal.r-universe.dev/PhysioCore/reference/physio-registry.html))
so other packages can discover and dispatch to them. `overwrite = TRUE`
keeps registration idempotent across reloads. PhysioCore is a hard
dependency, so its registry is initialized before this hook runs.

## Usage

``` r
.onLoad(libname, pkg)
```

## Arguments

- libname:

  Library path.

- pkg:

  Package name.
