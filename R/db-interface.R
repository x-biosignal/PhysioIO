#' Lightweight database interface
#'
#' These functions establish a connection to a DuckDB database using the
#' `DBI` interface. They form a minimal skeleton to be expanded with concrete
#' schema management functions in future iterations.
#'
#' @param path Path to a DuckDB database file.
#' @return A database connection object.
#' @references
#'   Raasveldt M, Muehleisen H (2019). "DuckDB: an embeddable analytical
#'   database." Proceedings of the 2019 International Conference on
#'   Management of Data (SIGMOD). doi:10.1145/3299869.3320212
#' @seealso \code{\link{initPhysioSchema}}, \code{\link{registerExperiment}},
#'   \code{\link{queryExperiments}}
#' @export
#' @examples
#' # DuckDB is an optional dependency; guard the example so it only runs
#' # when the package is installed.
#' if (requireNamespace("duckdb", quietly = TRUE)) {
#'   tf <- tempfile(fileext = ".duckdb")
#'   con <- connectDatabase(tf)
#'   # Always disconnect when done
#'   disconnectDatabase(con)
#'   unlink(tf)
#' }
connectDatabase <- function(path = ":memory:") {
  if (!requireNamespace("duckdb", quietly = TRUE)) {
    stop("Package 'duckdb' required for database operations. ",
         "Install with: install.packages('duckdb')", call. = FALSE)
  }
  DBI::dbConnect(duckdb::duckdb(), dbdir = path, read_only = FALSE)
}

#' @rdname connectDatabase
#' @param con A database connection produced by `connectDatabase()`.
#' @export
disconnectDatabase <- function(con) {
  if (!inherits(con, "DBIConnection")) {
    stop("Object is not a DBI connection", call. = FALSE)
  }
  DBI::dbDisconnect(con, shutdown = TRUE)
  invisible(NULL)
}
