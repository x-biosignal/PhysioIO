# PhysioIO ![PhysioIO logo](reference/figures/logo.png)

**I/O Functions for PhysioExperiment Objects**

PhysioIO provides comprehensive file I/O capabilities for the
PhysioExperiment ecosystem. With 50 exported functions, it supports
reading and writing physiological signal data across all major formats
used in neuroscience, rehabilitation, and clinical research – including
EDF/EDF+, HDF5, BIDS, CSV, MATLAB .mat, and RDS. It also integrates with
DuckDB for efficient querying and management of large-scale
physiological datasets.

## Installation

You can install PhysioIO from
[r-universe](https://x-biosignal.r-universe.dev):

``` r

install.packages("PhysioIO",
  repos = c("https://x-biosignal.r-universe.dev", "https://cloud.r-project.org"))
```

Or install the development version from GitHub:

``` r

# install.packages("remotes")
remotes::install_github("x-biosignal/PhysioIO")
```

## Quick Start

``` r

library(PhysioIO)

# Read an EDF file into a PhysioExperiment object
pe <- readEDF("recording.edf")
pe
#> PhysioExperiment with 256000 timepoints x 32 channels
#> Sampling rate: 512 Hz | Duration: 500.0 s
#> Assays: raw

# Write to HDF5 for out-of-memory analysis of large datasets
writePhysioHDF5(pe, "recording.h5")
pe_h5 <- readPhysioHDF5("recording.h5")
isHDF5Backed(pe_h5)  # TRUE

# Export to BIDS format
writeBIDS(pe, path = "bids_dataset", subject = "01", session = "pre",
          task = "rest", modality = "eeg")

# Query from a DuckDB database
con <- physioDBConnect("experiments.duckdb")
physioDBRegister(con, pe, dataset_id = "rest_eeg_01")
pe_loaded <- physioDBLoad(con, "rest_eeg_01")
physioDBDisconnect(con)
```

## Features

### EDF/EDF+ Format

Full support for the European Data Format, the most widely used standard
for polysomnography, EEG, and clinical recordings:

- [`readEDF()`](https://x-biosignal.github.io/PhysioIO/reference/readEDF.md)
  – read EDF and EDF+ files with automatic header parsing
- [`writeEDF()`](https://x-biosignal.github.io/PhysioIO/reference/writeEDF.md)
  – write PhysioExperiment objects to EDF format

### HDF5 Format

High-performance hierarchical data format with out-of-memory support for
large datasets:

- [`readPhysioHDF5()`](https://x-biosignal.github.io/PhysioIO/reference/readPhysioHDF5.md)
  – read HDF5 files into PhysioExperiment objects
- [`writePhysioHDF5()`](https://x-biosignal.github.io/PhysioIO/reference/writePhysioHDF5.md)
  – write with optional chunking and compression
- [`isHDF5Backed()`](https://x-biosignal.github.io/PhysioIO/reference/isHDF5Backed.md)
  – check if an object uses on-disk HDF5 storage
- [`realizeHDF5()`](https://x-biosignal.github.io/PhysioIO/reference/realizeHDF5.md)
  – load HDF5-backed data into memory

### BIDS Format

Brain Imaging Data Structure support for standardized neuroimaging
datasets:

- [`readBIDS()`](https://x-biosignal.github.io/PhysioIO/reference/readBIDS.md)
  – read BIDS-formatted datasets with automatic metadata extraction
- [`writeBIDS()`](https://x-biosignal.github.io/PhysioIO/reference/writeBIDS.md)
  – export to BIDS-compliant directory structure
- [`validateBIDS()`](https://x-biosignal.github.io/PhysioIO/reference/validateBIDS.md)
  – check BIDS compliance of a dataset
- [`listBIDSSubjects()`](https://x-biosignal.github.io/PhysioIO/reference/listBIDSSubjects.md)
  /
  [`listBIDSSessions()`](https://x-biosignal.github.io/PhysioIO/reference/listBIDSSessions.md)
  – enumerate dataset contents

### CSV Format

Flexible CSV import and export for tabular physiological data and
clinical metadata:

- [`readCSV()`](https://x-biosignal.github.io/PhysioIO/reference/readCSV.md)
  – read CSV files with automatic channel detection
- [`writeCSV()`](https://x-biosignal.github.io/PhysioIO/reference/writeCSV.md)
  – export signal data and metadata to CSV
- Clinical metadata CSV functions for participant and session
  information

### MATLAB .mat Format

Interoperability with MATLAB-based analysis pipelines:

- [`readMAT()`](https://x-biosignal.github.io/PhysioIO/reference/readMAT.md)
  – import .mat files (v5 and v7.3/HDF5-based)
- [`writeMAT()`](https://x-biosignal.github.io/PhysioIO/reference/writeMAT.md)
  – export PhysioExperiment objects to .mat format

### RDS Format

Native R serialization for fast save/load workflows:

- [`readPhysio()`](https://x-biosignal.github.io/PhysioIO/reference/writePhysio.md)
  – read PhysioExperiment objects from RDS files
- [`writePhysio()`](https://x-biosignal.github.io/PhysioIO/reference/writePhysio.md)
  – save PhysioExperiment objects as RDS

### DuckDB Database Integration

Efficient database-backed storage and querying for large-scale studies:

- `physioDBConnect()` – connect to a DuckDB database
- `physioDBRegister()` – register a PhysioExperiment in the database
- `physioDBQuery()` – query experiments by metadata criteria
- `physioDBLoad()` – load experiments from the database
- `physioDBDisconnect()` – close the database connection

## Dependencies

- **R** (\>= 4.2)
- **[PhysioCore](https://github.com/x-biosignal/PhysioCore)**
- **HDF5Array**
- **rhdf5**
- **jsonlite**
- **DBI**

## PhysioExperiment Ecosystem

PhysioIO is the I/O layer of the PhysioExperiment ecosystem, a suite of
R packages for multi-modal physiological signal analysis:

| Package | Description |
|----|----|
| [PhysioCore](https://github.com/x-biosignal/PhysioCore) | Core data structures and accessors |
| **PhysioIO** | File I/O (EDF, HDF5, BIDS, CSV, MAT) |
| [PhysioPreprocess](https://github.com/x-biosignal/PhysioPreprocess) | Preprocessing (filters, ICA, resampling) |
| [PhysioAnalysis](https://github.com/x-biosignal/PhysioAnalysis) | Analysis and visualization |

Visit the [r-universe page](https://x-biosignal.r-universe.dev) to
browse all available packages.

## License

MIT License. See
[LICENSE](https://x-biosignal.github.io/PhysioIO/LICENSE) for details.

## Author

Yusuke Matsui

## Governance & support

Part of the [Physio ecosystem](https://x-biosignal.r-universe.dev).
Community and policy documents live in the umbrella repository:

- [Code of
  Conduct](https://github.com/x-biosignal/PhysioExperiment/blob/main/CODE_OF_CONDUCT.md)
- [Contributing](https://github.com/x-biosignal/PhysioExperiment/blob/main/CONTRIBUTING.md)
- [Governance](https://github.com/x-biosignal/PhysioExperiment/blob/main/GOVERNANCE.md)
- [Support](https://github.com/x-biosignal/PhysioExperiment/blob/main/SUPPORT.md)
- [Security
  policy](https://github.com/x-biosignal/PhysioExperiment/blob/main/SECURITY.md)
- [Deprecation & lifecycle
  policy](https://github.com/x-biosignal/PhysioExperiment/blob/main/DEPRECATION.md)
