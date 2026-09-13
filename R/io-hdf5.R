#' HDF5 Backend for PhysioExperiment
#'
#' Functions for reading and writing PhysioExperiment objects to HDF5 format,
#' supporting out-of-memory operations for large datasets.

#' Write PhysioExperiment to HDF5
#'
#' Saves a PhysioExperiment object to HDF5 format, enabling out-of-memory
#' access for large datasets.
#'
#' @param x A PhysioExperiment object.
#' @param path Path to the output HDF5 file.
#' @param overwrite Logical. If TRUE, overwrites existing file.
#' @param chunk_dims Optional integer vector specifying chunk dimensions for
#'   HDF5 storage. If \code{NULL}, defaults are chosen automatically.
#' @param compression_level Integer compression level (0-9). Default is 6.
#' @return Invisible \code{NULL}. The HDF5 file is written to \code{path} as
#'   a side effect.
#' @references
#'   The HDF Group (1997-2024). "Hierarchical Data Format, version 5."
#'   \url{https://www.hdfgroup.org/HDF5/}
#' @seealso \code{\link{readPhysioHDF5}}, \code{\link{isHDF5Backed}},
#'   \code{\link{realizeHDF5}}, \code{\link{writeAssayHDF5}}
#' @export
#' @examples
#' # Create a PhysioExperiment
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
#'   samplingRate = 100
#' )
#'
#' # Save to a temporary HDF5 file with compression
#' tmp <- tempfile(fileext = ".h5")
#' writePhysioHDF5(pe, tmp, compression_level = 6)
#'
#' # Overwrite the existing file
#' writePhysioHDF5(pe, tmp, overwrite = TRUE)
#'
#' unlink(tmp)
writePhysioHDF5 <- function(x, path, overwrite = FALSE, chunk_dims = NULL,
                            compression_level = 6L) {
  stopifnot(inherits(x, "PhysioExperiment"))

  if (file.exists(path)) {
    if (overwrite) {
      file.remove(path)
    } else {
      stop("File already exists. Use overwrite = TRUE to replace.", call. = FALSE)
    }
  }

  rhdf5::h5createFile(path)

  # Create root groups
  rhdf5::h5createGroup(path, "/assays")

  # Write assays
  assay_names <- SummarizedExperiment::assayNames(x)

  for (name in assay_names) {
    data <- SummarizedExperiment::assay(x, name)
    dims <- dim(data)

    # Determine chunk dimensions
    if (is.null(chunk_dims)) {
      # Default chunking: balance between access patterns
      chunk <- pmin(dims, c(1000, rep(10, length(dims) - 1)))
    } else {
      chunk <- chunk_dims
    }

    dataset_path <- paste0("/assays/", name)

    rhdf5::h5createDataset(
      path, dataset_path,
      dims = dims,
      chunk = chunk,
      level = compression_level
    )
    rhdf5::h5write(as.array(data), path, dataset_path)
  }

  # Write metadata
  rhdf5::h5createGroup(path, "/metadata")

  # Sampling rate
  rhdf5::h5write(samplingRate(x), path, "/metadata/samplingRate")

  # Row data (time/sample metadata)
  row_data <- SummarizedExperiment::rowData(x)
  if (nrow(row_data) > 0) {
    rhdf5::h5createGroup(path, "/rowData")
    for (col in names(row_data)) {
      rhdf5::h5write(as.vector(row_data[[col]]), path, paste0("/rowData/", col))
    }
  }

  # Column data (channel metadata)
  col_data <- SummarizedExperiment::colData(x)
  if (nrow(col_data) > 0) {
    rhdf5::h5createGroup(path, "/colData")
    for (col in names(col_data)) {
      rhdf5::h5write(as.vector(col_data[[col]]), path, paste0("/colData/", col))
    }
  }

  # Events if present
  events <- S4Vectors::metadata(x)$events
  if (!is.null(events) && inherits(events, "PhysioEvents")) {
    rhdf5::h5createGroup(path, "/events")
    event_df <- events@events
    rhdf5::h5write(event_df$onset, path, "/events/onset")
    rhdf5::h5write(event_df$duration, path, "/events/duration")
    rhdf5::h5write(as.character(event_df$type), path, "/events/type")
    rhdf5::h5write(as.character(event_df$value), path, "/events/value")
  }

  # Additional metadata as JSON
  meta <- S4Vectors::metadata(x)
  meta$events <- NULL  # Already saved separately
  if (length(meta) > 0) {
    meta_json <- .metadataToJSON(meta)
    rhdf5::h5write(meta_json, path, "/metadata/extra")
  }

  # Bundle a W3C PROV-JSON provenance sidecar (no-op if no provenance)
  .writeProvSidecar(x, path)

  invisible(NULL)
}

#' Read PhysioExperiment from HDF5
#'
#' Reads a PhysioExperiment object from HDF5 format. By default, returns
#' DelayedArray-backed assays for out-of-memory processing.
#'
#' @param path Path to the HDF5 file.
#' @param as_delayed Logical. If TRUE (default), returns DelayedArray-backed
#'   assays. If FALSE, loads data into memory.
#' @return A \code{\link[PhysioCore:PhysioExperiment-class]{PhysioExperiment}}
#'   object. When
#'   \code{as_delayed = TRUE}, assays are \code{HDF5Array} objects enabling
#'   out-of-memory access; when \code{FALSE}, assays are standard in-memory
#'   arrays.
#' @references
#'   The HDF Group (1997-2024). "Hierarchical Data Format, version 5."
#'   \url{https://www.hdfgroup.org/HDF5/}
#' @seealso \code{\link{writePhysioHDF5}}, \code{\link{isHDF5Backed}},
#'   \code{\link{realizeHDF5}}, \code{\link{writeAssayHDF5}}
#' @export
#' @examples
#' # Write a small PhysioExperiment to a temporary HDF5 file
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
#'   samplingRate = 100
#' )
#' tmp <- tempfile(fileext = ".h5")
#' writePhysioHDF5(pe, tmp)
#'
#' # Read it back with the DelayedArray backend (out-of-memory)
#' pe_delayed <- readPhysioHDF5(tmp)
#' isHDF5Backed(pe_delayed)  # TRUE
#'
#' # Read it back into memory
#' pe_mem <- readPhysioHDF5(tmp, as_delayed = FALSE)
#' isHDF5Backed(pe_mem)  # FALSE
#'
#' unlink(tmp)
readPhysioHDF5 <- function(path, as_delayed = TRUE) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }

  # Read assay names
  h5_structure <- rhdf5::h5ls(path)
  h5_entries <- ifelse(
    h5_structure$group == "/",
    paste0("/", h5_structure$name),
    paste0(h5_structure$group, "/", h5_structure$name)
  )
  assay_entries <- h5_structure[h5_structure$group == "/assays", ]
  assay_names <- assay_entries$name

  # Read assays
  assay_list <- list()
  for (name in assay_names) {
    dataset_path <- paste0("/assays/", name)
    if (as_delayed) {
      assay_list[[name]] <- HDF5Array::HDF5Array(path, dataset_path)
    } else {
      assay_list[[name]] <- rhdf5::h5read(path, dataset_path)
    }
  }
  assays <- S4Vectors::SimpleList(assay_list)

  if (length(assay_list) > 0) {
    first_dims <- dim(assay_list[[1]])
    n_rows <- as.integer(first_dims[1])
    n_cols <- if (length(first_dims) >= 2) as.integer(first_dims[2]) else 0L
  } else {
    n_rows <- 0L
    n_cols <- 0L
  }

  # Read sampling rate
  sr <- as.numeric(rhdf5::h5read(path, "/metadata/samplingRate"))[1]

  # Read row data
  row_data <- S4Vectors::DataFrame(row.names = seq_len(n_rows))
  if ("/rowData" %in% h5_entries) {
    row_entries <- h5_structure[h5_structure$group == "/rowData", ]
    for (col in row_entries$name) {
      row_data[[col]] <- rhdf5::h5read(path, paste0("/rowData/", col))
    }
  }

  # Read column data
  col_data <- S4Vectors::DataFrame(row.names = seq_len(n_cols))
  if ("/colData" %in% h5_entries) {
    col_entries <- h5_structure[h5_structure$group == "/colData", ]
    for (col in col_entries$name) {
      col_data[[col]] <- rhdf5::h5read(path, paste0("/colData/", col))
    }
  }

  # Read events
  events <- NULL
  if (any(h5_structure$group == "/events")) {
    onset <- rhdf5::h5read(path, "/events/onset")
    duration <- rhdf5::h5read(path, "/events/duration")
    type <- rhdf5::h5read(path, "/events/type")
    value <- rhdf5::h5read(path, "/events/value")
    events <- PhysioEvents(onset, duration, type, value)
  }

  # Read additional metadata
  meta <- list()
  if ("/metadata/extra" %in% h5_entries) {
    meta_json <- as.character(rhdf5::h5read(path, "/metadata/extra"))[1]
    meta <- .JSONToMetadata(meta_json)
  }
  if (!is.null(events)) {
    meta$events <- events
  }
  meta$hdf5_file <- path

  # Create PhysioExperiment
  PhysioExperiment(
    assays = assays,
    rowData = row_data,
    colData = col_data,
    metadata = meta,
    samplingRate = sr
  )
}

#' Check if assays are HDF5-backed
#'
#' Tests whether the default assay of a PhysioExperiment is stored as an
#' HDF5-backed DelayedArray.
#'
#' @param x A PhysioExperiment object.
#' @return Logical scalar; \code{TRUE} if the default assay inherits from
#'   \code{HDF5Array} or \code{DelayedArray}, \code{FALSE} otherwise.
#' @references
#'   The HDF Group (1997-2024). "Hierarchical Data Format, version 5."
#'   \url{https://www.hdfgroup.org/HDF5/}
#' @seealso \code{\link{readPhysioHDF5}}, \code{\link{writePhysioHDF5}},
#'   \code{\link{realizeHDF5}}
#' @export
#' @examples
#' # Regular in-memory PhysioExperiment
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(1:100, nrow = 10)),
#'   samplingRate = 100
#' )
#' isHDF5Backed(pe)  # FALSE
isHDF5Backed <- function(x) {
  stopifnot(inherits(x, "PhysioExperiment"))

  assay_name <- defaultAssay(x)
  if (is.na(assay_name)) return(FALSE)

  data <- SummarizedExperiment::assay(x, assay_name)
  inherits(data, "HDF5Array") || inherits(data, "DelayedArray")
}

#' Realize HDF5-backed data to memory
#'
#' Loads HDF5-backed assays into memory as regular arrays.
#'
#' @param x A PhysioExperiment object.
#' @param assays Optional character vector of assay names to realize.
#'   If NULL, realizes all assays.
#' @return A \code{\link[PhysioCore:PhysioExperiment-class]{PhysioExperiment}}
#'   object with the specified assays realized as in-memory arrays.
#' @references
#'   The HDF Group (1997-2024). "Hierarchical Data Format, version 5."
#'   \url{https://www.hdfgroup.org/HDF5/}
#' @seealso \code{\link{readPhysioHDF5}}, \code{\link{writePhysioHDF5}},
#'   \code{\link{isHDF5Backed}}
#' @export
#' @examples
#' # Write and read back HDF5-backed data
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
#'   samplingRate = 100
#' )
#' tmp <- tempfile(fileext = ".h5")
#' writePhysioHDF5(pe, tmp)
#' pe_delayed <- readPhysioHDF5(tmp)
#'
#' # Realize all assays to memory
#' pe_mem <- realizeHDF5(pe_delayed)
#' isHDF5Backed(pe_mem)  # FALSE
#'
#' unlink(tmp)
realizeHDF5 <- function(x, assays = NULL) {
  stopifnot(inherits(x, "PhysioExperiment"))

  if (is.null(assays)) {
    assays <- SummarizedExperiment::assayNames(x)
  }

  for (name in assays) {
    data <- SummarizedExperiment::assay(x, name)
    if (inherits(data, "DelayedArray")) {
      SummarizedExperiment::assay(x, name) <- as.array(data)
    }
  }

  x
}

#' Convert metadata to JSON string
#' @noRd
.metadataToJSON <- function(meta) {
  # Simple JSON serialization for basic types
  json_parts <- list()

  for (name in names(meta)) {
    val <- meta[[name]]
    if (is.null(val)) next

    if (is.character(val) && length(val) == 1) {
      json_parts[[name]] <- sprintf('"%s": "%s"', name, gsub('"', '\\"', val))
    } else if (is.numeric(val) && length(val) == 1) {
      json_parts[[name]] <- sprintf('"%s": %s', name, val)
    } else if (is.logical(val) && length(val) == 1) {
      json_parts[[name]] <- sprintf('"%s": %s', name, tolower(as.character(val)))
    }
  }

  paste0("{", paste(unlist(json_parts), collapse = ", "), "}")
}

#' Parse JSON string to metadata list
#' @noRd
.JSONToMetadata <- function(json_str) {
  # Simple JSON parsing for basic types
  if (is.null(json_str) || json_str == "" || json_str == "{}") {
    return(list())
  }

  # Remove outer braces and split by comma
  content <- gsub("^\\{|\\}$", "", json_str)
  if (nchar(content) == 0) return(list())

  pairs <- strsplit(content, ",\\s*(?=\")", perl = TRUE)[[1]]

  result <- list()
  for (pair in pairs) {
    match <- regexec('"([^"]+)":\\s*(.+)', pair)
    if (match[[1]][1] != -1) {
      parts <- regmatches(pair, match)[[1]]
      key <- parts[2]
      value <- parts[3]

      # Parse value
      if (grepl('^".*"$', value)) {
        result[[key]] <- gsub('^"|"$', '', value)
      } else if (value %in% c("true", "false")) {
        result[[key]] <- value == "true"
      } else {
        result[[key]] <- as.numeric(value)
      }
    }
  }

  result
}

#' Write assay to HDF5 file
#'
#' Writes a single assay to an existing HDF5 file.
#'
#' @param x A PhysioExperiment object.
#' @param path Path to the HDF5 file.
#' @param assay_name Character string naming the assay to write.
#' @param compression_level Integer compression level (0-9).
#' @return Invisible \code{NULL}. The assay is written to the HDF5 file as a
#'   side effect.
#' @references
#'   The HDF Group (1997-2024). "Hierarchical Data Format, version 5."
#'   \url{https://www.hdfgroup.org/HDF5/}
#' @seealso \code{\link{writePhysioHDF5}}, \code{\link{readPhysioHDF5}},
#'   \code{\link{realizeHDF5}}
#' @export
#' @examples
#' # Create a PhysioExperiment and write it to a temporary HDF5 file
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
#'   samplingRate = 100
#' )
#' tmp <- tempfile(fileext = ".h5")
#' writePhysioHDF5(pe, tmp)
#'
#' # Add a second assay to the object and write only that assay to the file
#' SummarizedExperiment::assay(pe, "scaled") <-
#'   SummarizedExperiment::assay(pe, "raw") * 2
#' writeAssayHDF5(pe, tmp, "scaled")
#'
#' unlink(tmp)
writeAssayHDF5 <- function(x, path, assay_name, compression_level = 6L) {
  stopifnot(inherits(x, "PhysioExperiment"))
  stopifnot(file.exists(path))

  data <- SummarizedExperiment::assay(x, assay_name)
  dims <- dim(data)
  chunk <- pmin(dims, c(1000, rep(10, length(dims) - 1)))

  dataset_path <- paste0("/assays/", assay_name)

  # Check if dataset exists
  h5_structure <- rhdf5::h5ls(path)
  existing <- paste0(h5_structure$group, "/", h5_structure$name)

  if (dataset_path %in% existing) {
    rhdf5::h5delete(path, dataset_path)
  }

  rhdf5::h5createDataset(
    path, dataset_path,
    dims = dims,
    chunk = chunk,
    level = compression_level
  )
  rhdf5::h5write(as.array(data), path, dataset_path)

  invisible(NULL)
}
