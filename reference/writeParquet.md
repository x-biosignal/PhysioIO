# Write a PhysioExperiment to a Parquet dataset directory

Serialises a `PhysioExperiment` (or `MultiRatePhysioExperiment`) to a
directory of Apache Parquet tables and JSON sidecars. Each assay is
stored as a columnar Parquet table (one column per channel), and
`colData`, `rowData`, events, metadata, provenance and per-assay
sampling rates are stored alongside so that
[`readParquet()`](https://x-biosignal.github.io/PhysioIO/reference/readParquet.md)
reproduces the object exactly.

## Usage

``` r
writeParquet(x, dir, overwrite = FALSE)
```

## Arguments

- x:

  A `PhysioExperiment` or `MultiRatePhysioExperiment`.

- dir:

  Output directory (created if absent).

- overwrite:

  Overwrite a non-empty directory (default `FALSE`).

## Value

The output `dir`, invisibly.

## Details

Parquet is a columnar, self-describing format that DuckDB can query in
place via `read_parquet()`, enabling out-of-core aggregation over the
assays without loading them into R (see
[`registerParquetAssay()`](https://x-biosignal.github.io/PhysioIO/reference/registerParquetAssay.md)).

A `MultiRatePhysioExperiment` is written as a `streams/` sub-directory
(one Parquet dataset per stream) plus its common clock (t0, reference
rate, per-stream offsets).

## References

Apache Software Foundation. "Apache Parquet."
<https://parquet.apache.org/>.

## See also

[`readParquet()`](https://x-biosignal.github.io/PhysioIO/reference/readParquet.md),
[`registerParquetAssay()`](https://x-biosignal.github.io/PhysioIO/reference/registerParquetAssay.md),
[`writePhysioHDF5()`](https://x-biosignal.github.io/PhysioIO/reference/writePhysioHDF5.md)

## Examples

``` r
if (requireNamespace("arrow", quietly = TRUE)) {
  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = matrix(rnorm(30), 10, 3)),
    colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz")),
    samplingRate = 256)
  d <- tempfile("pe-parquet")
  writeParquet(pe, d)
  pe2 <- readParquet(d)
}
```
