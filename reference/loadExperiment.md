# Load experiment from database

Reconstructs a PhysioExperiment object from database records.

## Usage

``` r
loadExperiment(con, experiment_id, load_signals = FALSE)
```

## Arguments

- con:

  A DuckDB connection.

- experiment_id:

  The experiment identifier.

- load_signals:

  If TRUE, loads signal data from chunks.

## Value

A PhysioExperiment object.

## References

Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
database." Proceedings of the 2019 International Conference on
Management of Data (SIGMOD). doi:10.1145/3299869.3320212

## See also

[`registerExperiment`](https://x-biosignal.github.io/PhysioIO/reference/registerExperiment.md),
[`queryExperiments`](https://x-biosignal.github.io/PhysioIO/reference/queryExperiments.md),
[`deleteExperiment`](https://x-biosignal.github.io/PhysioIO/reference/deleteExperiment.md)

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
    subject_id = "sub01", task = "rest", store_signals = TRUE)
  # Reconstruct the object, with signal data
  pe2 <- loadExperiment(con, "demo1", load_signals = TRUE)
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
