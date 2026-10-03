#' PhysioIO: File and Database I/O for the Physio Ecosystem
#'
#' Reading and writing physiological signal data across the formats used in
#' neuroscience, rehabilitation and clinical research, plus a DuckDB-backed store
#' for large collections. Readers return a `PhysioExperiment` object (from
#' \pkg{PhysioExperiment}); writers take one and serialize it. Several readers
#' depend on optional back ends (e.g. `reticulate` for the MNE bridge); see each
#' function's help.
#'
#' @section Native R serialization (RDS):
#' [readPhysio()], [writePhysio()].
#'
#' @section Clinical and EEG recording formats:
#' EDF/EDF+ [readEDF()], [writeEDF()]; BioSemi BDF [readBDF()], [writeBDF()],
#' [readBDFStatus()], [bdfTriggerEvents()]; BrainVision [readBrainVision()],
#' [writeBrainVision()]; GDF [readGDF()], [writeGDF()]; Elekta/Neuromag FIF
#' [readFIF()].
#'
#' @section Large and columnar stores:
#' HDF5 (out-of-memory) [readPhysioHDF5()], [writePhysioHDF5()],
#' [isHDF5Backed()], [realizeHDF5()], [writeAssayHDF5()]; Arrow/Parquet
#' [readParquet()], [writeParquet()], [registerParquetAssay()].
#'
#' @section BIDS datasets:
#' [readBIDS()], [writeBIDS()], [validateBIDS()], [listBIDSSubjects()],
#' [listBIDSSessions()]; motion/physio/derivatives [readBIDSMotion()],
#' [writeBIDSMotion()], [readBIDSPhysio()], [writeBIDSPhysio()],
#' [attachBIDSPhysio()], [readBIDSDerivatives()], [writeBIDSDerivative()].
#'
#' @section CSV and clinical metadata:
#' [readCSV()], [writeCSV()], [readEventsCSV()], [writeEventsCSV()],
#' [readElectrodePositionsCSV()], [writeElectrodePositionsCSV()],
#' [readClinicalMetadataCSV()], [validateClinicalMetadata()], [mapClinicalCodes()].
#'
#' @section MATLAB and the MNE-Python bridge:
#' [readMAT()], [writeMAT()]; [toMNE()], [fromMNE()], [hasMNE()], [pyMNEVersion()].
#'
#' @section PhysioNet (WFDB) and public repositories:
#' [readWFDB()], [writeWFDB()], [readWFDBAnnotation()], [writeWFDBAnnotation()],
#' [listWFDBRecords()], [downloadPhysioNet()]; [downloadFigshare()],
#' [figshareCollectionArticles()], [downloadZenodo()], [downloadMendeley()],
#' [mendeleyDatasetFiles()], [downloadFromDOI()].
#'
#' @section Provenance and the DuckDB database:
#' W3C PROV [writeProv()], [readProv()]; database [connectDatabase()],
#' [disconnectDatabase()], [initPhysioSchema()], [registerExperiment()],
#' [queryExperiments()], [loadExperiment()], [deleteExperiment()], [dbStats()].
#'
#' @section Where to go next:
#' The data model and accessors live in \pkg{PhysioExperiment} (re-exported
#' here); preprocess with \pkg{PhysioPreprocess} and analyse with
#' \pkg{PhysioAnalysis}. See `vignette("file-formats", package = "PhysioIO")` and
#' `vignette("bids-database", package = "PhysioIO")`.
#'
#' @keywords internal
"_PACKAGE"
