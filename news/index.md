# Changelog

## PhysioIO 0.2.3

- [`readEDF()`](https://x-biosignal.github.io/PhysioIO/reference/readEDF.md)
  and
  [`readBrainVision()`](https://x-biosignal.github.io/PhysioIO/reference/readBrainVision.md)
  now record a W3C-PROV provenance activity for the read (the DAG root),
  capturing the source file path, so a loaded object carries its origin
  and the read step is visible to the reproducibility substrate
  run-tracing. This is separate from the existing on-disk provenance
  serialization (io-prov.R). No change to parsing.

## PhysioIO 0.2.2

### Bug Fixes

- `readFIF(backend = "native")` now decodes channel names safely on real
  Neuromag/MNE files. FIFF strings are Latin-1 and NUL-terminated within
  a fixed field; the previous code stripped every NUL (appending
  post-terminator padding) and left the string in an unknown encoding,
  so a non-ASCII byte or trailing padding made
  [`trimws()`](https://rdrr.io/r/base/trimws.html) abort with “invalid
  UTF-8”. The name is now truncated at the first NUL and decoded Latin-1
  to UTF-8, matching MNE. Adds a bundled MNE-written parity fixture and
  Latin-1 regression tests.

## PhysioIO 0.2.1

### Bug Fixes

- [`initPhysioSchema()`](https://x-biosignal.github.io/PhysioIO/reference/initPhysioSchema.md)
  now stores the experiment `metadata` column as `VARCHAR` instead of
  DuckDB’s `JSON` type. The `JSON` type requires DuckDB’s `json`
  extension, which DuckDB attempts to auto-download on first use; this
  failed in offline build environments (such as the r-universe source
  builder), breaking the `bids-database` vignette and the database
  example. Metadata is serialized and parsed with `jsonlite` in R, so a
  plain string column is fully equivalent and removes the extension
  dependency. Existing databases are unaffected; metadata continues to
  round-trip identically.

## PhysioIO 0.2.0

Initial release of PhysioIO as a standalone package in the x-biosignal
ecosystem, split out from the original PhysioExperiment monolith.
PhysioIO provides input, output, and database integration for
`SummarizedExperiment`-derived physiological signal containers, covering
the file formats and storage backends common in EEG, PSG, ECG, and BCI
research.

### New Features

- Native binary readers and writers for the standard biosignal formats,
  each returning or serialising a `PhysioExperiment` object with channel
  metadata and recording information preserved:
  - EDF / EDF+ via
    [`readEDF()`](https://x-biosignal.github.io/PhysioIO/reference/readEDF.md)
    and
    [`writeEDF()`](https://x-biosignal.github.io/PhysioIO/reference/writeEDF.md),
    including per-channel sampling-rate resampling, channel and
    time-window subsetting, and header parsing (labels, transducers,
    physical dimensions, patient metadata).
  - BDF via
    [`readBDF()`](https://x-biosignal.github.io/PhysioIO/reference/readBDF.md)
    and
    [`writeBDF()`](https://x-biosignal.github.io/PhysioIO/reference/writeBDF.md).
  - GDF (1.x and 2.x) via
    [`readGDF()`](https://x-biosignal.github.io/PhysioIO/reference/readGDF.md)
    and
    [`writeGDF()`](https://x-biosignal.github.io/PhysioIO/reference/writeGDF.md)
    for BCI workflows.
  - BrainVision (`.vhdr` / `.vmrk` / `.eeg`) via
    [`readBrainVision()`](https://x-biosignal.github.io/PhysioIO/reference/readBrainVision.md)
    and
    [`writeBrainVision()`](https://x-biosignal.github.io/PhysioIO/reference/writeBrainVision.md),
    one of the official BIDS-EEG formats.
- BIDS-EEG / BIDS-iEEG support via
  [`readBIDS()`](https://x-biosignal.github.io/PhysioIO/reference/readBIDS.md)
  and
  [`writeBIDS()`](https://x-biosignal.github.io/PhysioIO/reference/writeBIDS.md),
  with dataset navigation and validation helpers
  [`listBIDSSubjects()`](https://x-biosignal.github.io/PhysioIO/reference/listBIDSSubjects.md),
  [`listBIDSSessions()`](https://x-biosignal.github.io/PhysioIO/reference/listBIDSSessions.md),
  and
  [`validateBIDS()`](https://x-biosignal.github.io/PhysioIO/reference/validateBIDS.md).
- Tabular I/O via
  [`readCSV()`](https://x-biosignal.github.io/PhysioIO/reference/readCSV.md)
  /
  [`writeCSV()`](https://x-biosignal.github.io/PhysioIO/reference/writeCSV.md)
  (wide and long layouts, optional time column or sampling-rate-derived
  time), plus companion readers/writers for events
  ([`readEventsCSV()`](https://x-biosignal.github.io/PhysioIO/reference/readEventsCSV.md),
  [`writeEventsCSV()`](https://x-biosignal.github.io/PhysioIO/reference/writeEventsCSV.md))
  and electrode positions
  ([`readElectrodePositionsCSV()`](https://x-biosignal.github.io/PhysioIO/reference/readElectrodePositionsCSV.md),
  [`writeElectrodePositionsCSV()`](https://x-biosignal.github.io/PhysioIO/reference/writeElectrodePositionsCSV.md)).
- MATLAB `.mat` I/O via
  [`readMAT()`](https://x-biosignal.github.io/PhysioIO/reference/readMAT.md)
  and
  [`writeMAT()`](https://x-biosignal.github.io/PhysioIO/reference/writeMAT.md)
  (backed by `R.matlab`, with a pluggable backend option for testing).
- RDS round-trip helpers
  [`readPhysio()`](https://x-biosignal.github.io/PhysioIO/reference/writePhysio.md)
  and
  [`writePhysio()`](https://x-biosignal.github.io/PhysioIO/reference/writePhysio.md)
  for fast native serialisation of `PhysioExperiment` objects.
- Clinical / EDC metadata integration:
  - [`readClinicalMetadataCSV()`](https://x-biosignal.github.io/PhysioIO/reference/readClinicalMetadataCSV.md)
    loads assessment tables keyed on `subject_id` / `visit_id` for
    linking sessions to clinical variables.
  - [`validateClinicalMetadata()`](https://x-biosignal.github.io/PhysioIO/reference/validateClinicalMetadata.md)
    checks required columns and value ranges.
  - [`mapClinicalCodes()`](https://x-biosignal.github.io/PhysioIO/reference/mapClinicalCodes.md)
    recodes categorical clinical fields.

### Major Improvements

- HDF5 storage backend for out-of-memory work with large recordings:
  - [`writePhysioHDF5()`](https://x-biosignal.github.io/PhysioIO/reference/writePhysioHDF5.md)
    /
    [`readPhysioHDF5()`](https://x-biosignal.github.io/PhysioIO/reference/readPhysioHDF5.md)
    write and read chunked, compressed HDF5 datasets, with reads
    returning delayed `HDF5Array`-backed assays.
  - [`isHDF5Backed()`](https://x-biosignal.github.io/PhysioIO/reference/isHDF5Backed.md)
    and
    [`realizeHDF5()`](https://x-biosignal.github.io/PhysioIO/reference/realizeHDF5.md)
    inspect and materialise delayed assays;
    [`writeAssayHDF5()`](https://x-biosignal.github.io/PhysioIO/reference/writeAssayHDF5.md)
    exports an individual assay to HDF5.
- DuckDB database integration for cataloguing and querying many
  recordings:
  - [`connectDatabase()`](https://x-biosignal.github.io/PhysioIO/reference/connectDatabase.md)
    /
    [`disconnectDatabase()`](https://x-biosignal.github.io/PhysioIO/reference/connectDatabase.md)
    manage connections and
    [`initPhysioSchema()`](https://x-biosignal.github.io/PhysioIO/reference/initPhysioSchema.md)
    builds the relational schema (experiments, channels, signals,
    events).
  - [`registerExperiment()`](https://x-biosignal.github.io/PhysioIO/reference/registerExperiment.md)
    catalogues a `PhysioExperiment` (with optional signal storage), and
    [`loadExperiment()`](https://x-biosignal.github.io/PhysioIO/reference/loadExperiment.md)
    reconstructs it from the database.
  - [`queryExperiments()`](https://x-biosignal.github.io/PhysioIO/reference/queryExperiments.md)
    filters the catalogue by subject, task, and date range;
    [`deleteExperiment()`](https://x-biosignal.github.io/PhysioIO/reference/deleteExperiment.md)
    removes entries;
    [`dbStats()`](https://x-biosignal.github.io/PhysioIO/reference/dbStats.md)
    summarises the database contents.

### Documentation

- Every exported function ships roxygen2 documentation with runnable,
  temp-file-based round-trip examples and primary-source format
  references (EDF, BIDS, HDF5, DuckDB).
