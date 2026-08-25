#' Basic read/write helpers
#'
#' These helper functions provide a lightweight interface to serialise and
#' deserialise `PhysioExperiment` objects to RDS files. They act as placeholders
#' for richer IO backends that can be developed later.
#'
#' @param x A `PhysioExperiment` object.
#' @param path Path to an `.rds` file.
#' @return `readPhysio()` returns a
#'   \code{\link[PhysioCore:PhysioExperiment-class]{PhysioExperiment}} object.
#'   `writePhysio()` returns the input object invisibly.
#' @references
#'   Wickham, H. (2014). "Tidy Data." Journal of Statistical Software,
#'   59(10), 1-23. doi:10.18637/jss.v059.i10
#' @seealso \code{\link{readEDF}}, \code{\link{readPhysioHDF5}},
#'   \code{\link{readCSV}}, \code{\link{readMAT}}
#' @export
#' @examples
#' # Create a PhysioExperiment object
#' pe <- PhysioExperiment(
#'   assays = list(raw = matrix(rnorm(1000), nrow = 100, ncol = 10)),
#'   samplingRate = 256
#' )
#'
#' # Write to a temporary file
#' tmp <- tempfile(fileext = ".rds")
#' writePhysio(pe, tmp)
#'
#' # Read it back
#' pe_loaded <- readPhysio(tmp)
#' samplingRate(pe_loaded)
#'
#' # Clean up
#' unlink(tmp)
writePhysio <- function(x, path) {
  stopifnot(inherits(x, "PhysioExperiment"))
  saveRDS(x, file = path)
  invisible(x)
}

#' @rdname writePhysio
#' @export
readPhysio <- function(path) {
  if (!file.exists(path)) {
    stop(sprintf("File not found: %s", path), call. = FALSE)
  }
  obj <- readRDS(path)
  if (!inherits(obj, "PhysioExperiment")) {
    stop("File does not contain a PhysioExperiment object", call. = FALSE)
  }
  obj
}
