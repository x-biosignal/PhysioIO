library(testthat)
library(PhysioIO)

# Skip tests if DBI/duckdb not available
skip_if_not_installed("DBI")
skip_if_not_installed("duckdb")

make_test_pe <- function() {
  n_samples <- 100
  n_channels <- 3

  data <- matrix(rnorm(n_samples * n_channels), nrow = n_samples, ncol = n_channels)

  # rowData must have n_samples rows (matching dim[1] = time points)
  row_data <- S4Vectors::DataFrame(time_idx = seq_len(n_samples))

  # colData must have n_channels rows (matching dim[2] = channels)
  col_data <- S4Vectors::DataFrame(
    label = c("Fp1", "Fp2", "Cz"),
    type = c("EEG", "EEG", "EEG"),
    unit = c("uV", "uV", "uV")
  )

  # Database storage path persists continuous signals as 2D (time x channel)
  assays <- S4Vectors::SimpleList(raw = data)
  pe <- PhysioExperiment(assays, rowData = row_data, colData = col_data,
                         samplingRate = 250)

  # Add events
  events <- PhysioEvents(
    onset = c(0.1, 0.5, 0.8),
    duration = c(0, 0, 0),
    type = c("stimulus", "stimulus", "response"),
    value = c("1", "2", "1")
  )
  pe <- setEvents(pe, events)

  pe
}

test_that("initPhysioSchema creates tables", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  tables <- DBI::dbListTables(con)
  expect_true("experiments" %in% tables)
  expect_true("channels" %in% tables)
  expect_true("events" %in% tables)
  expect_true("signal_chunks" %in% tables)
  expect_true("epochs" %in% tables)
  expect_true("annotations" %in% tables)
})

test_that("registerExperiment stores metadata", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  pe <- make_test_pe()
  exp_id <- registerExperiment(con, pe, experiment_id = "test_exp",
                                subject_id = "subj01", task = "rest")

  expect_equal(exp_id, "test_exp")

  # Query experiments
  result <- DBI::dbGetQuery(con, "SELECT * FROM experiments WHERE experiment_id = 'test_exp'")
  expect_equal(nrow(result), 1)
  expect_equal(result$subject_id, "subj01")
  expect_equal(result$task, "rest")
  expect_equal(result$n_channels, 3)
  expect_equal(result$sampling_rate, 250)
})

test_that("registerExperiment stores channels", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  pe <- make_test_pe()
  registerExperiment(con, pe, experiment_id = "test_exp")

  channels <- DBI::dbGetQuery(con, "SELECT * FROM channels WHERE experiment_id = 'test_exp'")
  expect_equal(nrow(channels), 3)
  expect_true("Fp1" %in% channels$label)
  expect_true("Fp2" %in% channels$label)
  expect_true("Cz" %in% channels$label)
})

test_that("registerExperiment stores events", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  pe <- make_test_pe()
  registerExperiment(con, pe, experiment_id = "test_exp")

  events <- DBI::dbGetQuery(con, "SELECT * FROM events WHERE experiment_id = 'test_exp'")
  expect_equal(nrow(events), 3)
  expect_true("stimulus" %in% events$event_type)
  expect_true("response" %in% events$event_type)
})

test_that("registerExperiment stores signals when requested", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  pe <- make_test_pe()
  registerExperiment(con, pe, experiment_id = "test_exp",
                      store_signals = TRUE, chunk_size = 50)

  chunks <- DBI::dbGetQuery(con, "SELECT * FROM signal_chunks WHERE experiment_id = 'test_exp'")
  # 100 samples / 50 chunk_size = 2 chunks per channel, 3 channels = 6 chunks
  expect_equal(nrow(chunks), 6)
})

test_that("queryExperiments filters correctly", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  pe <- make_test_pe()
  registerExperiment(con, pe, experiment_id = "exp1", subject_id = "subj01", task = "rest")
  registerExperiment(con, pe, experiment_id = "exp2", subject_id = "subj01", task = "task")
  registerExperiment(con, pe, experiment_id = "exp3", subject_id = "subj02", task = "rest")

  # Filter by subject
  result <- queryExperiments(con, subject_id = "subj01")
  expect_equal(nrow(result), 2)

  # Filter by task
  result <- queryExperiments(con, task = "rest")
  expect_equal(nrow(result), 2)

  # Filter by both
  result <- queryExperiments(con, subject_id = "subj01", task = "rest")
  expect_equal(nrow(result), 1)
  expect_equal(result$experiment_id, "exp1")
})

test_that("queryExperiments filters by date range", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  pe <- make_test_pe()
  registerExperiment(con, pe, experiment_id = "exp1")
  registerExperiment(con, pe, experiment_id = "exp2")

  today <- as.character(Sys.Date())
  in_range <- queryExperiments(con, date_range = c(today, today))
  expect_equal(nrow(in_range), 2)

  out_range <- queryExperiments(con, date_range = c("1900-01-01", "1900-01-02"))
  expect_equal(nrow(out_range), 0)
})

test_that("loadExperiment reconstructs PhysioExperiment", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  pe <- make_test_pe()
  registerExperiment(con, pe, experiment_id = "test_exp",
                      subject_id = "subj01", task = "rest")

  # Load without signals
  loaded <- loadExperiment(con, "test_exp", load_signals = FALSE)

  expect_s4_class(loaded, "PhysioExperiment")
  expect_equal(samplingRate(loaded), 250)
  expect_equal(nChannels(loaded), 3)

  # Check metadata
  meta <- S4Vectors::metadata(loaded)
  expect_equal(meta$subject_id, "subj01")
  expect_equal(meta$task, "rest")
})

test_that("loadExperiment loads signals", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  pe <- make_test_pe()
  orig_data <- SummarizedExperiment::assay(pe)
  registerExperiment(con, pe, experiment_id = "test_exp", store_signals = TRUE)

  loaded <- loadExperiment(con, "test_exp", load_signals = TRUE)
  loaded_data <- SummarizedExperiment::assay(loaded)

  expect_equal(dim(loaded_data), dim(orig_data))
  expect_equal(loaded_data, orig_data, tolerance = 1e-10)
})

test_that("loadExperiment restores events", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  pe <- make_test_pe()
  registerExperiment(con, pe, experiment_id = "test_exp")

  loaded <- loadExperiment(con, "test_exp")
  events <- getEvents(loaded)

  expect_equal(nEvents(events), 3)
})

test_that("deleteExperiment removes all related records", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  pe <- make_test_pe()
  registerExperiment(con, pe, experiment_id = "test_exp", store_signals = TRUE)

  deleteExperiment(con, "test_exp", confirm = FALSE)

  # Check all tables are empty for this experiment
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) FROM experiments")[[1]], 0)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) FROM channels")[[1]], 0)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) FROM events")[[1]], 0)
  expect_equal(DBI::dbGetQuery(con, "SELECT COUNT(*) FROM signal_chunks")[[1]], 0)
})

test_that("dbStats returns correct counts", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  pe <- make_test_pe()
  registerExperiment(con, pe, experiment_id = "exp1", subject_id = "subj01", task = "rest")
  registerExperiment(con, pe, experiment_id = "exp2", subject_id = "subj02", task = "task")

  stats <- dbStats(con)

  expect_equal(stats$n_experiments, 2)
  expect_equal(stats$n_channels, 6)  # 3 channels per experiment
  expect_equal(stats$n_events, 6)    # 3 events per experiment
  expect_true("subj01" %in% stats$subjects)
  expect_true("subj02" %in% stats$subjects)
  expect_true("rest" %in% stats$tasks)
  expect_true("task" %in% stats$tasks)
})

test_that("loadExperiment errors on missing experiment", {
  con <- DBI::dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  initPhysioSchema(con)

  expect_error(loadExperiment(con, "nonexistent"), "not found")
})

test_that("initPhysioSchema validates connection", {
  expect_error(initPhysioSchema("not_a_connection"), "Invalid database connection")
})
