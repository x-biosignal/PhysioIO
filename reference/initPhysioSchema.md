# DuckDB Schema Management for PhysioExperiment

Functions for managing experiment data in DuckDB database. Provides a
relational schema for storing metadata, signals, and events. Initialize
PhysioExperiment database schema

## Usage

``` r
initPhysioSchema(con)
```

## Arguments

- con:

  A DuckDB connection from connectDatabase().

## Value

Invisible NULL.

## Details

Creates the database tables for storing experiment metadata, signals,
and events.

## References

Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
database." Proceedings of the 2019 International Conference on
Management of Data (SIGMOD). doi:10.1145/3299869.3320212

## See also

[`connectDatabase`](https://x-biosignal.github.io/PhysioIO/reference/connectDatabase.md),
[`registerExperiment`](https://x-biosignal.github.io/PhysioIO/reference/registerExperiment.md),
[`dbStats`](https://x-biosignal.github.io/PhysioIO/reference/dbStats.md)

## Examples

``` r
# DuckDB is an optional dependency; guard the example so it only runs
# when the package is installed.
if (requireNamespace("duckdb", quietly = TRUE)) {
  tf <- tempfile(fileext = ".duckdb")
  con <- connectDatabase(tf)
  initPhysioSchema(con)
  # Freshly created schema has no experiments yet
  dbStats(con)$n_experiments
  disconnectDatabase(con)
  unlink(tf)
}
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmp2gsje7/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
```
