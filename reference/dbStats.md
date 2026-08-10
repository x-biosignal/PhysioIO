# Get database statistics

Get database statistics

## Usage

``` r
dbStats(con)
```

## Arguments

- con:

  A DuckDB connection.

## Value

A list with database statistics.

## References

Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
database." Proceedings of the 2019 International Conference on
Management of Data (SIGMOD). doi:10.1145/3299869.3320212

## See also

[`connectDatabase`](https://x-biosignal.github.io/PhysioIO/reference/connectDatabase.md),
[`initPhysioSchema`](https://x-biosignal.github.io/PhysioIO/reference/initPhysioSchema.md),
[`queryExperiments`](https://x-biosignal.github.io/PhysioIO/reference/queryExperiments.md)

## Examples

``` r
# DuckDB is an optional dependency; guard the example so it only runs
# when the package is installed.
if (requireNamespace("duckdb", quietly = TRUE)) {
  tf <- tempfile(fileext = ".duckdb")
  con <- connectDatabase(tf)
  initPhysioSchema(con)
  stats <- dbStats(con)
  stats$n_experiments
  disconnectDatabase(con)
  unlink(tf)
}
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/Rtmpa6DD5K/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
```
