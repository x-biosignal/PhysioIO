# Register a Parquet-backed assay as a DuckDB view for out-of-core queries

Creates (or replaces) a DuckDB view over an assay Parquet file written
by
[`writeParquet()`](https://x-biosignal.github.io/PhysioIO/reference/writeParquet.md),
using DuckDB's `read_parquet()` so that aggregates are computed directly
over the file without loading it into R. The view columns are `ch1`,
`ch2`, ... (one per channel).

## Usage

``` r
registerParquetAssay(con, dir, view_name = "signals", assay = NULL)
```

## Arguments

- con:

  A DuckDB connection (from
  [`connectDatabase()`](https://x-biosignal.github.io/PhysioIO/reference/connectDatabase.md)).

- dir:

  A directory written by
  [`writeParquet()`](https://x-biosignal.github.io/PhysioIO/reference/writeParquet.md).

- view_name:

  Name of the DuckDB view to create (default `"signals"`).

- assay:

  Assay to expose; defaults to the manifest's default assay.

## Value

The `view_name`, invisibly.

## See also

[`writeParquet()`](https://x-biosignal.github.io/PhysioIO/reference/writeParquet.md),
[`registerExperiment()`](https://x-biosignal.github.io/PhysioIO/reference/registerExperiment.md)
