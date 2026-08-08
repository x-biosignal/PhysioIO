# Guide to Supported File Formats

## Overview

PhysioIO provides read and write support for the most common file
formats used in physiological signal research. This vignette walks
through each format, explains when to use it, and demonstrates the basic
API using self-contained round-trips through temporary files.

| Format | Read | Write | Package dependency |
|----|:--:|:--:|:--:|
| EDF/EDF+ | [`readEDF()`](https://x-biosignal.github.io/PhysioIO/reference/readEDF.md) | [`writeEDF()`](https://x-biosignal.github.io/PhysioIO/reference/writeEDF.md) | (none – built-in) |
| HDF5 | [`readPhysioHDF5()`](https://x-biosignal.github.io/PhysioIO/reference/readPhysioHDF5.md) | [`writePhysioHDF5()`](https://x-biosignal.github.io/PhysioIO/reference/writePhysioHDF5.md) | rhdf5, HDF5Array |
| CSV/TSV | [`readCSV()`](https://x-biosignal.github.io/PhysioIO/reference/readCSV.md) | [`writeCSV()`](https://x-biosignal.github.io/PhysioIO/reference/writeCSV.md) | (none – built-in) |
| MATLAB .mat | [`readMAT()`](https://x-biosignal.github.io/PhysioIO/reference/readMAT.md) | [`writeMAT()`](https://x-biosignal.github.io/PhysioIO/reference/writeMAT.md) | R.matlab |
| RDS | [`readPhysio()`](https://x-biosignal.github.io/PhysioIO/reference/writePhysio.md) | [`writePhysio()`](https://x-biosignal.github.io/PhysioIO/reference/writePhysio.md) | (none – built-in) |

All readers return a `PhysioExperiment` object, so downstream analysis
code is identical regardless of the input format.

``` r

library(PhysioIO)
#> Loading required package: PhysioCore
#> Warning: replacing previous import 'S4Arrays::makeNindexFromArrayViewport' by
#> 'DelayedArray::makeNindexFromArrayViewport' when loading 'SummarizedExperiment'
#> Warning: replacing previous import 'S4Arrays::makeNindexFromArrayViewport' by
#> 'DelayedArray::makeNindexFromArrayViewport' when loading 'HDF5Array'
```

## A small example object

We build a small, deterministic `PhysioExperiment` in memory to use for
every round-trip below. Using constant data keeps the vignette fully
reproducible.

``` r

n_time <- 200
n_ch <- 3
pe <- PhysioExperiment(
  assays = list(raw = matrix(0, nrow = n_time, ncol = n_ch)),
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

## RDS (native R serialization)

For quick save/restore within R, you can serialize a `PhysioExperiment`
to an RDS file. This preserves all slots and metadata exactly and needs
no extra dependency.

``` r

tf <- tempfile(fileext = ".rds")
writePhysio(pe, tf)
pe_rds <- readPhysio(tf)
identical(dim(pe_rds), dim(pe))
#> [1] TRUE
unlink(tf)
```

## CSV / TSV

CSV is the most portable format and is useful for small- to medium-sized
datasets or for interoperability with spreadsheet software and
Python/pandas.

``` r

tf <- tempfile(fileext = ".csv")
writeCSV(pe, tf)
pe_csv <- readCSV(tf, sampling_rate = 256)
dim(pe_csv)
#> [1] 200   4
unlink(tf)
```

**Reference:** Wickham H (2014). “Tidy Data.” *Journal of Statistical
Software*, 59(10), 1–23.

## EDF / EDF+

European Data Format (EDF) is the *de facto* standard for
polysomnography and clinical EEG recordings. EDF+ extends the original
format with support for annotations and discontinuous recordings.

``` r

tf <- tempfile(fileext = ".edf")
writeEDF(pe, tf)
pe_edf <- readEDF(tf)
dim(pe_edf)
#> [1] 256   3
unlink(tf)
```

**Reference:** Kemp B, et al. (1992). “A simple format for exchange of
digitized polygraphic recordings.” *Electroencephalography and Clinical
Neurophysiology*, 82(5), 391–393.

## HDF5

HDF5 is ideal for large datasets because it supports chunked,
compressed, out-of-memory storage. PhysioIO uses the Bioconductor
`rhdf5` and `HDF5Array` packages so that the data can remain on disk
while you operate on it.

``` r

tf <- tempfile(fileext = ".h5")
writePhysioHDF5(pe, tf)

# Read back into memory
pe_h5 <- readPhysioHDF5(tf, as_delayed = FALSE)

# Keep data on disk (HDF5-backed / delayed)
pe_lazy <- readPhysioHDF5(tf, as_delayed = TRUE)
isHDF5Backed(pe_lazy)
#> [1] TRUE
unlink(tf)
```

**Reference:** The HDF Group (1997–2024). “Hierarchical Data Format,
version 5.” <https://www.hdfgroup.org/HDF5/>

## MATLAB .mat files

PhysioIO can read and write MATLAB `.mat` files via the `R.matlab`
package. Auto-detection logic handles common EEG toolbox conventions
(EEGLAB, FieldTrip). The chunk below only evaluates when `R.matlab` is
installed.

``` r

tf <- tempfile(fileext = ".mat")
writeMAT(pe, tf)
pe_mat <- readMAT(tf)
dim(pe_mat)
#> [1] 200   3
unlink(tf)
```

**Reference:** MathWorks (2024). “MAT-File Format.” Technical
documentation.
<https://www.mathworks.com/help/matlab/import_export/mat-file-versions.html>

## Choosing a format

| Scenario                      | Recommended format    |
|-------------------------------|-----------------------|
| Long-term archival or sharing | EDF or HDF5           |
| Very large datasets (\> 1 GB) | HDF5 (on-disk)        |
| Interoperability with Python  | CSV or HDF5           |
| Interoperability with MATLAB  | .mat                  |
| BIDS-compliant data sharing   | BIDS (EDF underneath) |
| Quick R-only save/restore     | RDS                   |

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
#> [1] PhysioIO_0.2.2   PhysioCore_0.2.0 BiocStyle_2.40.0
#> 
#> loaded via a namespace (and not attached):
#>  [1] sass_0.4.10                 generics_0.1.4             
#>  [3] SparseArray_1.12.2          lattice_0.22-9             
#>  [5] h5mread_1.4.0               digest_0.6.39              
#>  [7] evaluate_1.0.5              grid_4.6.1                 
#>  [9] bookdown_0.47               fastmap_1.2.0              
#> [11] R.oo_1.27.1                 jsonlite_2.0.0             
#> [13] Matrix_1.7-5                R.utils_2.13.0             
#> [15] DBI_1.3.0                   BiocManager_1.30.27        
#> [17] HDF5Array_1.40.0            textshaping_1.0.5          
#> [19] jquerylib_0.1.4             abind_1.4-8                
#> [21] cli_3.6.6                   rlang_1.3.0                
#> [23] XVector_0.52.0              R.methodsS3_1.8.2          
#> [25] Biobase_2.72.0              R.matlab_3.7.0             
#> [27] cachem_1.1.0                DelayedArray_0.38.2        
#> [29] yaml_2.3.12                 otel_0.2.0                 
#> [31] S4Arrays_1.12.0             tools_4.6.1                
#> [33] Rhdf5lib_2.0.0              SummarizedExperiment_1.42.0
#> [35] BiocGenerics_0.58.1         R6_2.6.1                   
#> [37] matrixStats_1.5.0           stats4_4.6.1               
#> [39] lifecycle_1.0.5             rhdf5_2.56.0               
#> [41] Seqinfo_1.2.0               S4Vectors_0.50.1           
#> [43] fs_2.1.0                    IRanges_2.46.0             
#> [45] ragg_1.5.2                  desc_1.4.3                 
#> [47] pkgdown_2.2.1               bslib_0.12.0               
#> [49] systemfonts_1.3.2           xfun_0.60                  
#> [51] GenomicRanges_1.64.0        MatrixGenerics_1.24.0      
#> [53] knitr_1.51                  rhdf5filters_1.24.1        
#> [55] htmltools_0.5.9             rmarkdown_2.31             
#> [57] compiler_4.6.1
```
