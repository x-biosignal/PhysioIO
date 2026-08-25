# Standardized provenance capture for PhysioIO readers/constructors.
#
# .recordProv() appends exactly one W3C PROV activity to a PhysioExperiment
# returned by a reader/op, auto-capturing the calling function's name (as the
# PROV activity) and its atomic-valued arguments (as params, so a file `path`
# string is captured), and stamping the package version as the software agent.
# It is a silent no-op when the result is not a PhysioExperiment (e.g. a
# MultiRatePhysioExperiment), so callers can invoke it unconditionally right
# before returning.
# suppression flag so a function that delegates to another wired function
# internally records only its own (outer) activity, not the inner one.
.prov_env <- new.env(parent = emptyenv())
.prov_env$suppress <- FALSE

.suppressProvenance <- function(expr) {
  old <- .prov_env$suppress
  .prov_env$suppress <- TRUE
  on.exit(.prov_env$suppress <- old)
  expr
}

.recordProv <- function(result, input_assay = NA_character_,
                        output_assay = NA_character_,
                        .package = "PhysioIO", from = NULL) {
  if (!inherits(result, "PhysioExperiment")) return(result)
  if (isTRUE(.prov_env$suppress)) return(result)
  # carry a freshly-constructed object's history from its source input
  if (inherits(from, "PhysioExperiment")) {
    fp <- S4Vectors::metadata(from)[["provenance"]]
    rp <- S4Vectors::metadata(result)[["provenance"]]
    if (!is.null(fp) && length(fp) > (if (is.null(rp)) 0L else length(rp))) {
      S4Vectors::metadata(result)[["provenance"]] <- fp
    }
  }
  fn <- tryCatch({
    cc <- as.character(sys.call(-1L)[[1L]]); cc[length(cc)]
  }, error = function(e) "op")
  if (length(fn) != 1L || is.na(fn) || !nzchar(fn)) fn <- "op"
  pf <- parent.frame()
  fmls <- tryCatch(names(formals(sys.function(-1L))), error = function(e) character(0))
  params <- list()
  for (nm in fmls) {
    if (nm == "..." || !exists(nm, envir = pf, inherits = FALSE)) next
    v <- tryCatch(get(nm, envir = pf, inherits = FALSE), error = function(e) NULL)
    if (is.null(v) || !is.atomic(v) || length(v) > 8L ||
        inherits(v, "PhysioExperiment")) next
    params[[nm]] <- v
  }
  ver <- tryCatch(as.character(utils::packageVersion(.package)),
                  error = function(e) NA_character_)
  PhysioCore::appendProvenance(result, activity = fn, params = params,
                               input_assay = input_assay,
                               output_assay = output_assay,
                               software_version = ver)
}
