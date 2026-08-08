# Register a PhysioExperiment in the database

Stores experiment metadata and optionally signal data in the database.

## Usage

``` r
registerExperiment(
  con,
  x,
  experiment_id = NULL,
  subject_id = NULL,
  session_id = NULL,
  task = NULL,
  store_signals = FALSE,
  chunk_size = 10000L,
  parquet_dir = NULL
)
```

## Arguments

- con:

  A DuckDB connection.

- x:

  A PhysioExperiment object.

- experiment_id:

  Unique identifier for the experiment.

- subject_id:

  Subject identifier.

- session_id:

  Session identifier.

- task:

  Task name.

- store_signals:

  If TRUE, stores signal data in chunks.

- chunk_size:

  Number of samples per chunk for signal storage.

- parquet_dir:

  Optional directory for a Parquet backend. When supplied, the
  experiment is written with
  [`writeParquet()`](https://x-biosignal.github.io/PhysioIO/reference/writeParquet.md)
  and its default assay is registered as a DuckDB view named
  `<experiment_id>_signals` via
  [`registerParquetAssay()`](https://x-biosignal.github.io/PhysioIO/reference/registerParquetAssay.md),
  enabling out-of-core queries over the Parquet file without loading
  signals into R.

## Value

The experiment_id.

## References

Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
database." Proceedings of the 2019 International Conference on
Management of Data (SIGMOD). doi:10.1145/3299869.3320212

## See also

[`loadExperiment`](https://x-biosignal.github.io/PhysioIO/reference/loadExperiment.md),
[`queryExperiments`](https://x-biosignal.github.io/PhysioIO/reference/queryExperiments.md),
[`deleteExperiment`](https://x-biosignal.github.io/PhysioIO/reference/deleteExperiment.md),
[`initPhysioSchema`](https://x-biosignal.github.io/PhysioIO/reference/initPhysioSchema.md)

## Examples

``` r
# DuckDB is an optional dependency; guard the example so it only runs
# when the package is installed.
if (requireNamespace("duckdb", quietly = TRUE)) {
  tf <- tempfile(fileext = ".duckdb")
  con <- connectDatabase(tf)
  initPhysioSchema(con)
  # Build a small deterministic PhysioExperiment
  pe <- PhysioExperiment(
    assays = list(raw = matrix(0, nrow = 100, ncol = 3)),
    colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz")),
    samplingRate = 256
  )
  exp_id <- registerExperiment(con, pe,
    experiment_id = "demo1", subject_id = "sub01", task = "rest")
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
