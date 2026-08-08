# Query experiments from database

Query experiments from database

## Usage

``` r
queryExperiments(con, subject_id = NULL, task = NULL, date_range = NULL)
```

## Arguments

- con:

  A DuckDB connection.

- subject_id:

  Optional filter by subject.

- task:

  Optional filter by task.

- date_range:

  Optional date range (vector of 2 dates).

## Value

A data.frame of matching experiments.

## References

Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
database." Proceedings of the 2019 International Conference on
Management of Data (SIGMOD). doi:10.1145/3299869.3320212

## See also

[`registerExperiment`](https://x-biosignal.github.io/PhysioIO/reference/registerExperiment.md),
[`loadExperiment`](https://x-biosignal.github.io/PhysioIO/reference/loadExperiment.md),
[`dbStats`](https://x-biosignal.github.io/PhysioIO/reference/dbStats.md)

## Examples

``` r
# DuckDB is an optional dependency; guard the example so it only runs
# when the package is installed.
if (requireNamespace("duckdb", quietly = TRUE)) {
  tf <- tempfile(fileext = ".duckdb")
  con <- connectDatabase(tf)
  initPhysioSchema(con)
  pe <- PhysioExperiment(
    assays = list(raw = matrix(0, nrow = 100, ncol = 3)),
    colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz")),
    samplingRate = 256
  )
  registerExperiment(con, pe, experiment_id = "demo1",
    subject_id = "sub01", task = "rest")
  # Query all experiments, or filter by subject / task
  all_exps <- queryExperiments(con)
  sub01_exps <- queryExperiments(con, subject_id = "sub01")
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
