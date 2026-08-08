# BIDS Format Support and DuckDB Backend

## Introduction

PhysioIO provides two complementary features for managing collections of
physiological recordings:

1.  **BIDS support** – read and write data in the Brain Imaging Data
    Structure (BIDS) format, the community standard for organizing
    neuroimaging and electrophysiology datasets.
2.  **DuckDB backend** – store experiment metadata, channel information,
    events, and (optionally) signal data in an embedded analytical
    database for fast querying across many sessions.

This vignette demonstrates both capabilities with self-contained,
runnable examples that write to temporary locations.

``` r

library(PhysioIO)
#> Loading required package: PhysioCore
#> Warning: replacing previous import 'S4Arrays::makeNindexFromArrayViewport' by
#> 'DelayedArray::makeNindexFromArrayViewport' when loading 'SummarizedExperiment'
#> Warning: replacing previous import 'S4Arrays::makeNindexFromArrayViewport' by
#> 'DelayedArray::makeNindexFromArrayViewport' when loading 'HDF5Array'
```

We use a small deterministic object throughout.

``` r

pe <- PhysioExperiment(
  assays = list(raw = matrix(0, nrow = 200, ncol = 3)),
  colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz")),
  samplingRate = 256
)
pe
#> class: PhysioExperiment
#> dim: 200 x 3 
#> assays(1): raw
#> samplingRate: 256 Hz
#> channels(3): Fp1, Fp2, Cz
#> colData names(1): label
```

## BIDS format support

### What is BIDS?

The Brain Imaging Data Structure (BIDS) is a standard for organizing
neuroimaging data into a consistent directory layout with
machine-readable metadata files. PhysioIO supports the BIDS-EEG and
BIDS-iEEG extensions.

**Reference:** Gorgolewski KJ, et al. (2016). “The brain imaging data
structure, a format for organizing and describing outputs of
neuroimaging experiments.” *Scientific Data*, 3, 160044.

### Writing to and reading from a BIDS dataset

[`writeBIDS()`](https://x-biosignal.github.io/PhysioIO/reference/writeBIDS.md)
creates the required directory structure, writes the EDF data file, and
generates the sidecar TSV and JSON files.
[`readBIDS()`](https://x-biosignal.github.io/PhysioIO/reference/readBIDS.md)
loads it back, merging information from the companion sidecars.

``` r

bids_root <- tempfile("bids")
dir.create(bids_root)

writeBIDS(pe, bids_root, subject = "01", task = "rest")

# Read a single recording back
pe_bids <- readBIDS(bids_root, subject = "01", task = "rest")
dim(pe_bids)
#> [1] 256   3
```

### Exploring and validating a BIDS dataset

``` r

# List all subjects
listBIDSSubjects(bids_root)
#> [1] "01"

# Validate BIDS compliance
result <- validateBIDS(bids_root)
result$valid
#> [1] TRUE
result$n_subjects
#> [1] 1
```

The validator checks for `dataset_description.json`, subject directory
naming, modality directories, and required metadata fields.

``` r

unlink(bids_root, recursive = TRUE)
```

## DuckDB database backend

### Why use a database?

When a study involves dozens or hundreds of recording sessions, it
becomes impractical to load every file just to find which subjects had a
particular task or which recordings fall within a date range. The DuckDB
backend lets you register experiment metadata once and query it
efficiently.

**Reference:** Raasveldt M, Muehleisen H (2019). “DuckDB: an embeddable
analytical database.” Proceedings of the 2019 International Conference
on Management of Data (SIGMOD).

The chunks below evaluate only when the optional `duckdb` package is
available.

### Connecting, initializing, registering, and querying

[`initPhysioSchema()`](https://x-biosignal.github.io/PhysioIO/reference/initPhysioSchema.md)
creates the `experiments`, `channels`, `events`, `signal_chunks`,
`epochs`, and `annotations` tables.

``` r

db_path <- tempfile(fileext = ".duckdb")
con <- connectDatabase(db_path)
#> duckdb keeps downloaded extensions and secrets in a temporary directory:
#> ℹ /tmp/RtmpeoRJTR/duckdb
#> This is removed when the R session ends.
#> • Extensions are re-downloaded each session.
#> • Secrets are lost.
#> ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
#> ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
#> ℹ See ?duckdb_storage for details and alternatives.
initPhysioSchema(con)

# Register metadata (and optionally signal data)
registerExperiment(con, pe,
  experiment_id = "demo1",
  subject_id = "sub-01",
  task = "rest",
  store_signals = TRUE
)
#> [1] "demo1"

# Query across sessions
all_exps <- queryExperiments(con)
sub01 <- queryExperiments(con, subject_id = "sub-01")

# Reload a registered experiment
pe_db <- loadExperiment(con, "demo1", load_signals = TRUE)
dim(pe_db)
#> [1] 200   3

# Summary statistics
stats <- dbStats(con)
stats$n_experiments
#> [1] 1

# Remove and disconnect
deleteExperiment(con, "demo1")
disconnectDatabase(con)
unlink(db_path)
```

## Session info

``` r

sessionInfo()
#> R version 4.6.1 (2026-06-24)
#> Platform: x86_64-pc-linux-gnu
#> Running under: Ubuntu 24.04.4 LTS
#> 
#> Matrix products: default
#> BLAS:   /usr/lib/x86_64-linux-gnu/openblas-pthread/libblas.so.3 
#> LAPACK: /usr/lib/x86_64-linux-gnu/openblas-pthread/libopenblasp-r0.3.26.so;  LAPACK version 3.12.0
#> 
#> locale:
#>  [1] LC_CTYPE=C.UTF-8       LC_NUMERIC=C           LC_TIME=C.UTF-8       
#>  [4] LC_COLLATE=C.UTF-8     LC_MONETARY=C.UTF-8    LC_MESSAGES=C.UTF-8   
#>  [7] LC_PAPER=C.UTF-8       LC_NAME=C              LC_ADDRESS=C          
#> [10] LC_TELEPHONE=C         LC_MEASUREMENT=C.UTF-8 LC_IDENTIFICATION=C   
#> 
#> time zone: UTC
#> tzcode source: system (glibc)
#> 
#> attached base packages:
#> [1] stats     graphics  grDevices utils     datasets  methods   base     
#> 
#> other attached packages:
#> [1] PhysioIO_0.2.2   PhysioCore_0.2.0
#> 
#> loaded via a namespace (and not attached):
#>  [1] sass_0.4.10                 generics_0.1.4             
#>  [3] SparseArray_1.12.2          lattice_0.22-9             
#>  [5] h5mread_1.4.0               digest_0.6.39              
#>  [7] evaluate_1.0.5              grid_4.6.1                 
#>  [9] fastmap_1.2.0               jsonlite_2.0.0             
#> [11] Matrix_1.7-5                DBI_1.3.0                  
#> [13] HDF5Array_1.40.0            textshaping_1.0.5          
#> [15] jquerylib_0.1.4             abind_1.4-8                
#> [17] duckdb_1.5.5                cli_3.6.6                  
#> [19] rlang_1.3.0                 XVector_0.52.0             
#> [21] Biobase_2.72.0              cachem_1.1.0               
#> [23] DelayedArray_0.38.2         yaml_2.3.12                
#> [25] otel_0.2.0                  S4Arrays_1.12.0            
#> [27] tools_4.6.1                 Rhdf5lib_2.0.0             
#> [29] SummarizedExperiment_1.42.0 BiocGenerics_0.58.1        
#> [31] R6_2.6.1                    matrixStats_1.5.0          
#> [33] stats4_4.6.1                lifecycle_1.0.5            
#> [35] rhdf5_2.56.0                Seqinfo_1.2.0              
#> [37] S4Vectors_0.50.1            fs_2.1.0                   
#> [39] IRanges_2.46.0              ragg_1.5.2                 
#> [41] desc_1.4.3                  pkgdown_2.2.1              
#> [43] bslib_0.12.0                systemfonts_1.3.2          
#> [45] xfun_0.60                   GenomicRanges_1.64.0       
#> [47] MatrixGenerics_1.24.0       knitr_1.51                 
#> [49] rhdf5filters_1.24.1         htmltools_0.5.9            
#> [51] rmarkdown_2.31              compiler_4.6.1
```
