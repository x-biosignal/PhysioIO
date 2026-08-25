#' Package on-load hook
#'
#' Advertises the readers/writers PhysioIO provides through the PhysioCore plugin
#' registry (see \code{PhysioCore::`physio-registry`}) so other packages can
#' discover and dispatch to them. \code{overwrite = TRUE} keeps registration
#' idempotent across reloads. PhysioCore is a hard dependency, so its registry is
#' initialized before this hook runs.
#'
#' @param libname Library path.
#' @param pkg Package name.
#' @keywords internal
.onLoad <- function(libname, pkg) {
  PhysioCore::registerReader("brainvision", readBrainVision, ext = "vhdr",
                             overwrite = TRUE)
  PhysioCore::registerWriter("brainvision", writeBrainVision, ext = "vhdr",
                             overwrite = TRUE)
  PhysioCore::registerReader("gdf", readGDF, ext = "gdf", overwrite = TRUE)
  PhysioCore::registerWriter("gdf", writeGDF, ext = "gdf", overwrite = TRUE)
  invisible(NULL)
}
