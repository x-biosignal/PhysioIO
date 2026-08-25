# PhysioIO 0.2.4

- New vignette `mne-interop` ("Interoperating with MNE-Python") documenting the `hasMNE()` / `toMNE()` / `fromMNE()` bridge and the ecosystem's interop-first, selectively-native strategy for brain-imaging integration (borrow MNE for individual-MRI source imaging + the long tail; keep native the reproducibility-substrate / PhysioAgent ops; use MNE as a validation oracle). Documentation only — the chunks require MNE-Python via reticulate and are not executed or tangled, so `R CMD check` and r-universe never initialise reticulate.
- Added a validation-oracle test to `test-bridge-mne.R`: MNE's PSD and an independent base-R periodogram agree on per-channel alpha power (spatial correlation > 0.99) on a synthetic alpha gradient. Like the other bridge tests it skips unless `reticulate` can reach a Python with `mne` (safe on CRAN / r-universe); a header comment documents how to run the MNE suite (`RETICULATE_PYTHON=…`).

# PhysioIO 0.2.3

- `readEDF()` and `readBrainVision()` now record a W3C-PROV provenance activity for the read (the DAG root), capturing the source file path, so a loaded object carries its origin and the read step is visible to the reproducibility substrate run-tracing. This is separate from the existing on-disk provenance serialization (io-prov.R). No change to parsing.

# PhysioIO 0.2.2

## Bug Fixes

- `readFIF(backend = "native")` now decodes channel names safely on real
  Neuromag/MNE files. FIFF strings are Latin-1 and NUL-terminated within a
  fixed field; the previous code stripped every NUL (appending post-terminator
  padding) and left the string in an unknown encoding, so a non-ASCII byte or
  trailing padding made `trimws()` abort with "invalid UTF-8". The name is now
  truncated at the first NUL and decoded Latin-1 to UTF-8, matching MNE. Adds a
  bundled MNE-written parity fixture and Latin-1 regression tests.

# PhysioIO 0.2.1

## Bug Fixes

- `initPhysioSchema()` now stores the experiment `metadata` column as `VARCHAR`
  instead of DuckDB's `JSON` type. The `JSON` type requires DuckDB's `json`
  extension, which DuckDB attempts to auto-download on first use; this failed in
  offline build environments (such as the r-universe source builder), breaking
  the `bids-database` vignette and the database example. Metadata is serialized
  and parsed with `jsonlite` in R, so a plain string column is fully equivalent
  and removes the extension dependency. Existing databases are unaffected;
  metadata continues to round-trip identically.

# PhysioIO 0.2.0

Initial release of PhysioIO as a standalone package in the x-biosignal
ecosystem, split out from the original PhysioExperiment monolith. PhysioIO
provides input, output, and database integration for
`SummarizedExperiment`-derived physiological signal containers, covering the
file formats and storage backends common in EEG, PSG, ECG, and BCI research.

## New Features

- Native binary readers and writers for the standard biosignal formats, each
  returning or serialising a `PhysioExperiment` object with channel metadata
  and recording information preserved:
  - EDF / EDF+ via `readEDF()` and `writeEDF()`, including per-channel
    sampling-rate resampling, channel and time-window subsetting, and header
    parsing (labels, transducers, physical dimensions, patient metadata).
  - BDF via `readBDF()` and `writeBDF()`.
  - GDF (1.x and 2.x) via `readGDF()` and `writeGDF()` for BCI workflows.
  - BrainVision (`.vhdr` / `.vmrk` / `.eeg`) via `readBrainVision()` and
    `writeBrainVision()`, one of the official BIDS-EEG formats.
- BIDS-EEG / BIDS-iEEG support via `readBIDS()` and `writeBIDS()`, with
  dataset navigation and validation helpers `listBIDSSubjects()`,
  `listBIDSSessions()`, and `validateBIDS()`.
- Tabular I/O via `readCSV()` / `writeCSV()` (wide and long layouts, optional
  time column or sampling-rate-derived time), plus companion readers/writers
  for events (`readEventsCSV()`, `writeEventsCSV()`) and electrode positions
  (`readElectrodePositionsCSV()`, `writeElectrodePositionsCSV()`).
- MATLAB `.mat` I/O via `readMAT()` and `writeMAT()` (backed by `R.matlab`,
  with a pluggable backend option for testing).
- RDS round-trip helpers `readPhysio()` and `writePhysio()` for fast native
  serialisation of `PhysioExperiment` objects.
- Clinical / EDC metadata integration:
  - `readClinicalMetadataCSV()` loads assessment tables keyed on
    `subject_id` / `visit_id` for linking sessions to clinical variables.
  - `validateClinicalMetadata()` checks required columns and value ranges.
  - `mapClinicalCodes()` recodes categorical clinical fields.

## Major Improvements

- HDF5 storage backend for out-of-memory work with large recordings:
  - `writePhysioHDF5()` / `readPhysioHDF5()` write and read chunked,
    compressed HDF5 datasets, with reads returning delayed `HDF5Array`-backed
    assays.
  - `isHDF5Backed()` and `realizeHDF5()` inspect and materialise delayed
    assays; `writeAssayHDF5()` exports an individual assay to HDF5.
- DuckDB database integration for cataloguing and querying many recordings:
  - `connectDatabase()` / `disconnectDatabase()` manage connections and
    `initPhysioSchema()` builds the relational schema (experiments, channels,
    signals, events).
  - `registerExperiment()` catalogues a `PhysioExperiment` (with optional
    signal storage), and `loadExperiment()` reconstructs it from the database.
  - `queryExperiments()` filters the catalogue by subject, task, and date
    range; `deleteExperiment()` removes entries; `dbStats()` summarises the
    database contents.

## Documentation

- Every exported function ships roxygen2 documentation with runnable,
  temp-file-based round-trip examples and primary-source format references
  (EDF, BIDS, HDF5, DuckDB).
