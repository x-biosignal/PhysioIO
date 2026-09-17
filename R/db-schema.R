#' DuckDB Schema Management for PhysioExperiment
#'
#' Functions for managing experiment data in DuckDB database.
#' Provides a relational schema for storing metadata, signals, and events.

#' Initialize PhysioExperiment database schema
#'
#' Creates the database tables for storing experiment metadata, signals, and events.
#'
#' @param con A DuckDB connection from connectDatabase().
#' @return Invisible NULL.
#' @references
#'   Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
#'   database." Proceedings of the 2019 International Conference on
#'   Management of Data (SIGMOD). doi:10.1145/3299869.3320212
#' @seealso \code{\link{connectDatabase}}, \code{\link{registerExperiment}},
#'   \code{\link{dbStats}}
#' @export
#' @examples
#' # DuckDB is an optional dependency; guard the example so it only runs
#' # when the package is installed.
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   tf <- tempfile(fileext = ".duckdb")
#'   con <- connectDatabase(tf)
#'   initPhysioSchema(con)
#'   # Freshly created schema has no experiments yet
#'   dbStats(con)$n_experiments
#'   disconnectDatabase(con)
#'   unlink(tf)
#' }
initPhysioSchema <- function(con) {
  if (!inherits(con, "DBIConnection")) {
    stop("Invalid database connection", call. = FALSE)
  }

  # Experiments table - main metadata.
  # `metadata` is stored as VARCHAR (a jsonlite-serialized string), not DuckDB's
  # JSON type: the JSON type pulls in the 'json' extension, which DuckDB tries to
  # auto-download on first use and fails in offline builds (e.g. r-universe).
  # All JSON handling happens in R via jsonlite, so a plain string is sufficient.
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS experiments (
      experiment_id VARCHAR PRIMARY KEY,
      subject_id VARCHAR,
      session_id VARCHAR,
      task VARCHAR,
      recording_date DATE,
      sampling_rate DOUBLE,
      n_channels INTEGER,
      n_samples BIGINT,
      duration_seconds DOUBLE,
      file_path VARCHAR,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      metadata VARCHAR
    )
  ")

  # Channels table - channel metadata
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS channels (
      channel_id VARCHAR PRIMARY KEY,
      experiment_id VARCHAR REFERENCES experiments(experiment_id),
      channel_index INTEGER,
      label VARCHAR,
      channel_type VARCHAR,
      unit VARCHAR,
      reference VARCHAR,
      pos_x DOUBLE,
      pos_y DOUBLE,
      pos_z DOUBLE,
      sampling_rate DOUBLE,
      UNIQUE(experiment_id, channel_index)
    )
  ")

  # Events table - experimental events
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS events (
      event_id VARCHAR PRIMARY KEY,
      experiment_id VARCHAR REFERENCES experiments(experiment_id),
      onset_seconds DOUBLE,
      duration_seconds DOUBLE,
      event_type VARCHAR,
      event_value VARCHAR,
      sample_index BIGINT
    )
  ")

  # Signal chunks table - for storing signal data in chunks
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS signal_chunks (
      chunk_id VARCHAR PRIMARY KEY,
      experiment_id VARCHAR REFERENCES experiments(experiment_id),
      channel_index INTEGER,
      start_sample BIGINT,
      end_sample BIGINT,
      data BLOB
    )
  ")

  # Epochs table - epoched data metadata
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS epochs (
      epoch_id VARCHAR PRIMARY KEY,
      experiment_id VARCHAR REFERENCES experiments(experiment_id),
      epoch_index INTEGER,
      event_type VARCHAR,
      event_value VARCHAR,
      tmin DOUBLE,
      tmax DOUBLE,
      baseline_corrected BOOLEAN DEFAULT FALSE,
      rejected BOOLEAN DEFAULT FALSE
    )
  ")

  # Annotations table - free-form annotations
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS annotations (
      annotation_id VARCHAR PRIMARY KEY,
      experiment_id VARCHAR REFERENCES experiments(experiment_id),
      start_seconds DOUBLE,
      end_seconds DOUBLE,
      description VARCHAR,
      annotator VARCHAR,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  ")

  # Create indexes for common queries
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_channels_exp ON channels(experiment_id)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_events_exp ON events(experiment_id)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_chunks_exp ON signal_chunks(experiment_id)")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_epochs_exp ON epochs(experiment_id)")

  invisible(NULL)
}

#' Register a PhysioExperiment in the database
#'
#' Stores experiment metadata and optionally signal data in the database.
#'
#' @param con A DuckDB connection.
#' @param x A PhysioExperiment object.
#' @param experiment_id Unique identifier for the experiment.
#' @param subject_id Subject identifier.
#' @param session_id Session identifier.
#' @param task Task name.
#' @param store_signals If TRUE, stores signal data in chunks.
#' @param chunk_size Number of samples per chunk for signal storage.
#' @param parquet_dir Optional directory for a Parquet backend. When supplied,
#'   the experiment is written with [writeParquet()] and its default assay is
#'   registered as a DuckDB view named \code{<experiment_id>_signals} via
#'   [registerParquetAssay()], enabling out-of-core queries over the Parquet
#'   file without loading signals into R.
#' @return The experiment_id.
#' @references
#'   Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
#'   database." Proceedings of the 2019 International Conference on
#'   Management of Data (SIGMOD). doi:10.1145/3299869.3320212
#' @seealso \code{\link{loadExperiment}}, \code{\link{queryExperiments}},
#'   \code{\link{deleteExperiment}}, \code{\link{initPhysioSchema}}
#' @export
#' @examples
#' # DuckDB is an optional dependency; guard the example so it only runs
#' # when the package is installed.
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   tf <- tempfile(fileext = ".duckdb")
#'   con <- connectDatabase(tf)
#'   initPhysioSchema(con)
#'   # Build a small deterministic PhysioExperiment
#'   pe <- PhysioExperiment(
#'     assays = list(raw = matrix(0, nrow = 100, ncol = 3)),
#'     colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz")),
#'     samplingRate = 256
#'   )
#'   exp_id <- registerExperiment(con, pe,
#'     experiment_id = "demo1", subject_id = "sub01", task = "rest")
#'   disconnectDatabase(con)
#'   unlink(tf)
#' }
registerExperiment <- function(con, x, experiment_id = NULL, subject_id = NULL,
                                session_id = NULL, task = NULL,
                                store_signals = FALSE, chunk_size = 10000L,
                                parquet_dir = NULL) {
  stopifnot(inherits(x, "PhysioExperiment"))

  if (is.null(experiment_id)) {
    experiment_id <- paste0("exp_", format(Sys.time(), "%Y%m%d%H%M%S"), "_",
                            sample(1000:9999, 1))
  }

  # Optional Parquet backend: persist the experiment and expose its default
  # assay as a DuckDB view. Done first (fail-fast) so a failure here leaves no
  # partial experiment/channel/event rows behind.
  if (!is.null(parquet_dir)) {
    writeParquet(x, parquet_dir, overwrite = TRUE)
    registerParquetAssay(con, parquet_dir,
                         view_name = paste0(experiment_id, "_signals"))
  }

  subject_id <- if (is.null(subject_id)) NA_character_ else as.character(subject_id)[1]
  session_id <- if (is.null(session_id)) NA_character_ else as.character(session_id)[1]
  task <- if (is.null(task)) NA_character_ else as.character(task)[1]

  # Get basic info
  sr <- as.numeric(samplingRate(x))[1]
  n_ch <- as.integer(nChannels(x))[1]
  n_samples <- as.integer(length(x))[1]
  dur <- if (!is.na(sr) && sr > 0) n_samples / sr else NA

  # Get metadata
  meta <- S4Vectors::metadata(x)

  # Prefer explicit recording date metadata; otherwise fall back to EDF-style
  # start_date; if unavailable, use registration date so date_range filters work.
  recording_date <- as.Date(NA)
  if (!is.null(meta$recording_date) && length(meta$recording_date) > 0) {
    recording_date <- suppressWarnings(as.Date(meta$recording_date[[1]]))
  }
  if (is.na(recording_date) && !is.null(meta$start_date) && length(meta$start_date) > 0) {
    recording_date <- suppressWarnings(as.Date(meta$start_date[[1]], format = "%d.%m.%y"))
  }
  if (is.na(recording_date)) {
    recording_date <- Sys.Date()
  }

  meta_json <- if (length(meta) > 0) {
    tryCatch(
      jsonlite::toJSON(meta, auto_unbox = TRUE),
      error = function(e) "{}"
    )
  } else {
    "{}"
  }

  # Insert experiment record
  DBI::dbExecute(con, "
    INSERT INTO experiments (experiment_id, subject_id, session_id, task,
                             recording_date, sampling_rate, n_channels, n_samples,
                             duration_seconds, metadata)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  ", params = list(experiment_id, subject_id, session_id, task,
                   as.character(recording_date), sr, n_ch, n_samples, dur,
                   as.character(meta_json)[1]))

  # Insert channel records
  ch_names <- channelNames(x)
  ch_info <- channelInfo(x)

  for (i in seq_len(n_ch)) {
    ch_id <- paste0(experiment_id, "_ch", i)

    ch_type <- if ("type" %in% names(ch_info)) ch_info$type[i] else NA
    ch_unit <- if ("unit" %in% names(ch_info)) ch_info$unit[i] else NA
    pos_x <- if ("pos_x" %in% names(ch_info)) ch_info$pos_x[i] else NA
    pos_y <- if ("pos_y" %in% names(ch_info)) ch_info$pos_y[i] else NA
    pos_z <- if ("pos_z" %in% names(ch_info)) ch_info$pos_z[i] else NA

    DBI::dbExecute(con, "
      INSERT INTO channels (channel_id, experiment_id, channel_index, label,
                           channel_type, unit, pos_x, pos_y, pos_z, sampling_rate)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ", params = list(ch_id, experiment_id, i, ch_names[i],
                     ch_type, ch_unit, pos_x, pos_y, pos_z, sr))
  }

  # Insert events if present
  events <- getEvents(x)
  if (nEvents(events) > 0) {
    event_df <- events@events

    for (i in seq_len(nrow(event_df))) {
      evt_id <- paste0(experiment_id, "_evt", i)
      sample_idx <- if (!is.na(sr)) as.integer(event_df$onset[i] * sr) else NA

      DBI::dbExecute(con, "
        INSERT INTO events (event_id, experiment_id, onset_seconds, duration_seconds,
                           event_type, event_value, sample_index)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      ", params = list(evt_id, experiment_id, event_df$onset[i], event_df$duration[i],
                       event_df$type[i], event_df$value[i], sample_idx))
    }
  }

  # Store signal data if requested
  if (store_signals) {
    assay_name <- defaultAssay(x)
    data <- SummarizedExperiment::assay(x, assay_name)
    dims <- dim(data)

    # Flatten to 2D if needed
    if (length(dims) == 3) {
      data <- data[, , 1]
    }

    n_chunks <- ceiling(nrow(data) / chunk_size)

    for (ch in seq_len(ncol(data))) {
      for (chunk in seq_len(n_chunks)) {
        start_sample <- (chunk - 1) * chunk_size + 1
        end_sample <- min(chunk * chunk_size, nrow(data))

        chunk_data <- data[start_sample:end_sample, ch]
        chunk_id <- paste0(experiment_id, "_ch", ch, "_chunk", chunk)

        # Serialize data as raw bytes
        raw_data <- serialize(chunk_data, NULL)

        DBI::dbExecute(con, "
          INSERT INTO signal_chunks (chunk_id, experiment_id, channel_index,
                                    start_sample, end_sample, data)
          VALUES (?, ?, ?, ?, ?, ?)
        ", params = list(chunk_id, experiment_id, ch, start_sample, end_sample,
                         list(raw_data)))
      }
    }
  }

  experiment_id
}

#' Query experiments from database
#'
#' @param con A DuckDB connection.
#' @param subject_id Optional filter by subject.
#' @param task Optional filter by task.
#' @param date_range Optional date range (vector of 2 dates).
#' @return A data.frame of matching experiments.
#' @references
#'   Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
#'   database." Proceedings of the 2019 International Conference on
#'   Management of Data (SIGMOD). doi:10.1145/3299869.3320212
#' @seealso \code{\link{registerExperiment}}, \code{\link{loadExperiment}},
#'   \code{\link{dbStats}}
#' @export
#' @examples
#' # DuckDB is an optional dependency; guard the example so it only runs
#' # when the package is installed.
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   tf <- tempfile(fileext = ".duckdb")
#'   con <- connectDatabase(tf)
#'   initPhysioSchema(con)
#'   pe <- PhysioExperiment(
#'     assays = list(raw = matrix(0, nrow = 100, ncol = 3)),
#'     colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz")),
#'     samplingRate = 256
#'   )
#'   registerExperiment(con, pe, experiment_id = "demo1",
#'     subject_id = "sub01", task = "rest")
#'   # Query all experiments, or filter by subject / task
#'   all_exps <- queryExperiments(con)
#'   sub01_exps <- queryExperiments(con, subject_id = "sub01")
#'   disconnectDatabase(con)
#'   unlink(tf)
#' }
queryExperiments <- function(con, subject_id = NULL, task = NULL, date_range = NULL) {
  query <- "SELECT * FROM experiments WHERE 1=1"
  params <- list()

  if (!is.null(subject_id)) {
    query <- paste(query, "AND subject_id = ?")
    params <- c(params, subject_id)
  }

  if (!is.null(task)) {
    query <- paste(query, "AND task = ?")
    params <- c(params, task)
  }

  if (!is.null(date_range)) {
    query <- paste(query, "AND recording_date BETWEEN ? AND ?")
    params <- c(params, as.character(date_range[1]), as.character(date_range[2]))
  }

  query <- paste(query, "ORDER BY created_at DESC")

  if (length(params) > 0) {
    DBI::dbGetQuery(con, query, params = params)
  } else {
    DBI::dbGetQuery(con, query)
  }
}

#' Load experiment from database
#'
#' Reconstructs a PhysioExperiment object from database records.
#'
#' @param con A DuckDB connection.
#' @param experiment_id The experiment identifier.
#' @param load_signals If TRUE, loads signal data from chunks.
#' @return A PhysioExperiment object.
#' @references
#'   Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
#'   database." Proceedings of the 2019 International Conference on
#'   Management of Data (SIGMOD). doi:10.1145/3299869.3320212
#' @seealso \code{\link{registerExperiment}}, \code{\link{queryExperiments}},
#'   \code{\link{deleteExperiment}}
#' @export
#' @examples
#' # DuckDB is an optional dependency; guard the example so it only runs
#' # when the package is installed.
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   tf <- tempfile(fileext = ".duckdb")
#'   con <- connectDatabase(tf)
#'   initPhysioSchema(con)
#'   pe <- PhysioExperiment(
#'     assays = list(raw = matrix(0, nrow = 100, ncol = 3)),
#'     colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz")),
#'     samplingRate = 256
#'   )
#'   registerExperiment(con, pe, experiment_id = "demo1",
#'     subject_id = "sub01", task = "rest", store_signals = TRUE)
#'   # Reconstruct the object, with signal data
#'   pe2 <- loadExperiment(con, "demo1", load_signals = TRUE)
#'   disconnectDatabase(con)
#'   unlink(tf)
#' }
loadExperiment <- function(con, experiment_id, load_signals = FALSE) {
  # Get experiment metadata
  exp_data <- DBI::dbGetQuery(con,
    "SELECT * FROM experiments WHERE experiment_id = ?",
    params = list(experiment_id)
  )

  if (nrow(exp_data) == 0) {
    stop("Experiment not found: ", experiment_id, call. = FALSE)
  }

  sr <- as.numeric(exp_data$sampling_rate[[1]])
  n_channels <- as.integer(exp_data$n_channels[[1]])
  n_samples <- as.integer(exp_data$n_samples[[1]])

  # Get channel info
  ch_data <- DBI::dbGetQuery(con,
    "SELECT * FROM channels WHERE experiment_id = ? ORDER BY channel_index",
    params = list(experiment_id)
  )

  # Get events
  evt_data <- DBI::dbGetQuery(con,
    "SELECT * FROM events WHERE experiment_id = ? ORDER BY onset_seconds",
    params = list(experiment_id)
  )

  # Load or create empty signals
  if (load_signals) {
    chunk_data <- DBI::dbGetQuery(con,
      "SELECT * FROM signal_chunks WHERE experiment_id = ? ORDER BY channel_index, start_sample",
      params = list(experiment_id)
    )

    if (nrow(chunk_data) > 0) {
      # Reconstruct signal matrix
      signal_matrix <- matrix(NA_real_, nrow = n_samples, ncol = n_channels)

      for (i in seq_len(nrow(chunk_data))) {
        ch <- chunk_data$channel_index[i]
        start <- chunk_data$start_sample[i]
        end <- chunk_data$end_sample[i]

        raw_data <- chunk_data$data[[i]]
        chunk_signal <- unserialize(raw_data)
        signal_matrix[start:end, ch] <- chunk_signal
      }
    } else {
      signal_matrix <- matrix(NA_real_, nrow = n_samples, ncol = n_channels)
    }
  } else {
    signal_matrix <- matrix(NA_real_, nrow = n_samples, ncol = n_channels)
  }

  # Build channel metadata aligned to assay columns.
  normalize_col <- function(x, n, mode = c("character", "numeric")) {
    mode <- match.arg(mode)

    if (length(x) == n) {
      return(if (mode == "numeric") as.numeric(x) else as.character(x))
    }

    if (mode == "numeric") {
      out <- rep(NA_real_, n)
      n_copy <- min(length(x), n)
      if (n_copy > 0) out[seq_len(n_copy)] <- as.numeric(x[seq_len(n_copy)])
    } else {
      out <- rep(NA_character_, n)
      n_copy <- min(length(x), n)
      if (n_copy > 0) out[seq_len(n_copy)] <- as.character(x[seq_len(n_copy)])
    }

    out
  }

  if (nrow(ch_data) > 0) {
    ch_label <- normalize_col(ch_data$label, n_channels, "character")
    ch_type <- normalize_col(ch_data$channel_type, n_channels, "character")
    ch_unit <- normalize_col(ch_data$unit, n_channels, "character")
    ch_pos_x <- normalize_col(ch_data$pos_x, n_channels, "numeric")
    ch_pos_y <- normalize_col(ch_data$pos_y, n_channels, "numeric")
    ch_pos_z <- normalize_col(ch_data$pos_z, n_channels, "numeric")
  } else {
    ch_label <- paste0("Ch", seq_len(n_channels))
    ch_type <- rep(NA_character_, n_channels)
    ch_unit <- rep(NA_character_, n_channels)
    ch_pos_x <- rep(NA_real_, n_channels)
    ch_pos_y <- rep(NA_real_, n_channels)
    ch_pos_z <- rep(NA_real_, n_channels)
  }

  # rowData indexes time points, colData indexes channels.
  row_data <- S4Vectors::DataFrame(time_idx = seq_len(n_samples))
  col_data <- S4Vectors::DataFrame(
    label = ch_label,
    type = ch_type,
    unit = ch_unit,
    pos_x = ch_pos_x,
    pos_y = ch_pos_y,
    pos_z = ch_pos_z
  )

  # Create metadata
  meta <- list(
    subject_id = exp_data$subject_id[[1]],
    session_id = exp_data$session_id[[1]],
    task = exp_data$task[[1]],
    recording_date = exp_data$recording_date[[1]],
    database_id = experiment_id
  )

  # Parse stored metadata JSON
  if (!is.na(exp_data$metadata[[1]]) && exp_data$metadata[[1]] != "{}") {
    tryCatch({
      stored_meta <- jsonlite::fromJSON(exp_data$metadata[[1]])
      meta <- c(meta, stored_meta)
    }, error = function(e) NULL)
  }

  # Create PhysioExperiment
  assays <- S4Vectors::SimpleList(raw = signal_matrix)

  pe <- PhysioExperiment(
    assays = assays,
    rowData = row_data,
    colData = col_data,
    metadata = meta,
    samplingRate = sr
  )

  # Add events
  if (nrow(evt_data) > 0) {
    pe <- setEvents(pe, PhysioEvents(
      onset = evt_data$onset_seconds,
      duration = evt_data$duration_seconds,
      type = evt_data$event_type,
      value = evt_data$event_value
    ))
  }

  pe
}

#' Delete experiment from database
#'
#' @param con A DuckDB connection.
#' @param experiment_id The experiment identifier.
#' @param confirm If TRUE, requires confirmation.
#' @return Invisible NULL.
#' @references
#'   Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
#'   database." Proceedings of the 2019 International Conference on
#'   Management of Data (SIGMOD). doi:10.1145/3299869.3320212
#' @seealso \code{\link{registerExperiment}}, \code{\link{loadExperiment}},
#'   \code{\link{queryExperiments}}
#' @export
#' @examples
#' # DuckDB is an optional dependency; guard the example so it only runs
#' # when the package is installed.
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   tf <- tempfile(fileext = ".duckdb")
#'   con <- connectDatabase(tf)
#'   initPhysioSchema(con)
#'   pe <- PhysioExperiment(
#'     assays = list(raw = matrix(0, nrow = 100, ncol = 3)),
#'     colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz")),
#'     samplingRate = 256
#'   )
#'   registerExperiment(con, pe, experiment_id = "demo1", subject_id = "sub01")
#'   # Remove the experiment and all related records
#'   deleteExperiment(con, "demo1")
#'   disconnectDatabase(con)
#'   unlink(tf)
#' }
deleteExperiment <- function(con, experiment_id, confirm = TRUE) {
  if (confirm) {
    # Check if experiment exists
    exists <- DBI::dbGetQuery(con,
      "SELECT COUNT(*) as n FROM experiments WHERE experiment_id = ?",
      params = list(experiment_id)
    )$n > 0

    if (!exists) {
      stop("Experiment not found: ", experiment_id, call. = FALSE)
    }
  }

  # Delete in order due to foreign keys
  DBI::dbExecute(con, "DELETE FROM signal_chunks WHERE experiment_id = ?",
                 params = list(experiment_id))
  DBI::dbExecute(con, "DELETE FROM epochs WHERE experiment_id = ?",
                 params = list(experiment_id))
  DBI::dbExecute(con, "DELETE FROM annotations WHERE experiment_id = ?",
                 params = list(experiment_id))
  DBI::dbExecute(con, "DELETE FROM events WHERE experiment_id = ?",
                 params = list(experiment_id))
  DBI::dbExecute(con, "DELETE FROM channels WHERE experiment_id = ?",
                 params = list(experiment_id))
  DBI::dbExecute(con, "DELETE FROM experiments WHERE experiment_id = ?",
                 params = list(experiment_id))

  invisible(NULL)
}

#' Get database statistics
#'
#' @param con A DuckDB connection.
#' @return A list with database statistics.
#' @references
#'   Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
#'   database." Proceedings of the 2019 International Conference on
#'   Management of Data (SIGMOD). doi:10.1145/3299869.3320212
#' @seealso \code{\link{connectDatabase}}, \code{\link{initPhysioSchema}},
#'   \code{\link{queryExperiments}}
#' @export
#' @examples
#' # DuckDB is an optional dependency; guard the example so it only runs
#' # when the package is installed.
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   tf <- tempfile(fileext = ".duckdb")
#'   con <- connectDatabase(tf)
#'   initPhysioSchema(con)
#'   stats <- dbStats(con)
#'   stats$n_experiments
#'   disconnectDatabase(con)
#'   unlink(tf)
#' }
dbStats <- function(con) {
  list(
    n_experiments = DBI::dbGetQuery(con, "SELECT COUNT(*) FROM experiments")[[1]],
    n_channels = DBI::dbGetQuery(con, "SELECT COUNT(*) FROM channels")[[1]],
    n_events = DBI::dbGetQuery(con, "SELECT COUNT(*) FROM events")[[1]],
    n_chunks = DBI::dbGetQuery(con, "SELECT COUNT(*) FROM signal_chunks")[[1]],
    subjects = DBI::dbGetQuery(con, "SELECT DISTINCT subject_id FROM experiments")[[1]],
    tasks = DBI::dbGetQuery(con, "SELECT DISTINCT task FROM experiments")[[1]]
  )
}
