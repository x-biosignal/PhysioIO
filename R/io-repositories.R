# Programmatic retrieval from public data repositories (figshare, Zenodo,
# Mendeley Data).
#
# These mirror downloadPhysioNet() in io-wfdb.R: base utils::download.file over
# the repositories' public REST APIs, optional checksum verification, and a
# tidy per-file data frame return (name, path, size, checksum, algo,
# checksum_ok). Many of the reproducible case studies in the ecosystem draw on
# figshare (GaitRec, WBDS, BDS), Zenodo and Mendeley Data datasets; these
# functions make that retrieval a first-class, provenance-friendly step instead
# of an ad-hoc curl call.
#
# Repository differences worth knowing:
#   * figshare / Zenodo -- files download anonymously; checksum is MD5.
#   * Mendeley Data      -- dataset & file METADATA (incl. SHA-256) are public,
#                           but downloading file BYTES requires an OAuth token;
#                           checksum is SHA-256.

# ---- internal helpers -------------------------------------------------------

# Default-if-NULL/empty.
.pio_or <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

# Fetch a JSON document over HTTP and parse it (as a nested list).
.pio_fetch_json <- function(url, headers = NULL) {
  tmp <- tempfile(fileext = ".json")
  on.exit(unlink(tmp), add = TRUE)
  ok <- tryCatch({
    if (is.null(headers)) utils::download.file(url, tmp, mode = "wb", quiet = TRUE)
    else utils::download.file(url, tmp, mode = "wb", quiet = TRUE, headers = headers)
    TRUE
  }, error = function(e) FALSE)
  if (!ok || !file.exists(tmp) || file.info(tmp)$size == 0)
    stop(sprintf(
      "Failed to fetch metadata from %s (offline, rate-limited, or record not found).",
      url), call. = FALSE)
  jsonlite::fromJSON(tmp, simplifyVector = FALSE)
}

# Download one file, optionally verifying it against a checksum of the given
# algorithm ("md5", "sha256", ...). Returns TRUE/FALSE (match) or NA when no
# checksum is available. Re-downloads a pre-existing file only if its checksum
# is known-bad; bumps the download timeout for large files; sends optional HTTP
# headers (e.g. an Authorization bearer token).
.pio_download_file <- function(url, out, hash = NULL, algo = "md5", verify = TRUE,
                               overwrite = FALSE, quiet = TRUE, headers = NULL) {
  check <- function() {
    if (is.null(hash) || !nzchar(hash)) return(NA)
    identical(tolower(digest::digest(file = out, algo = algo)), tolower(hash))
  }
  have <- file.exists(out) && file.info(out)$size > 0
  if (have && !overwrite) {
    ok <- check()
    if (isTRUE(ok) || is.na(ok)) return(ok)   # good, or unverifiable
    # known-bad checksum on the existing file: fall through and re-download
  }
  old <- options(timeout = max(getOption("timeout", 60L), 3600L))
  on.exit(options(old), add = TRUE)
  ok <- tryCatch({
    if (is.null(headers)) utils::download.file(url, out, mode = "wb", quiet = quiet)
    else utils::download.file(url, out, mode = "wb", quiet = quiet, headers = headers)
    TRUE
  }, error = function(e) FALSE)
  if (!ok || !file.exists(out))
    stop(sprintf("Download failed: %s", url), call. = FALSE)
  hok <- check()
  if (verify && isFALSE(hok)) {
    # a small JSON/HTML body served in place of the file is an auth/expiry error
    peek <- tryCatch(readChar(out, 400L, useBytes = TRUE), error = function(e) "")
    if (file.info(out)$size < 8192L &&
        grepl('"(error|code)"[[:space:]]*:[[:space:]]*404|not found|<!?html|<head',
              peek, ignore.case = TRUE))
      stop(sprintf(
        "Server returned an error page, not file content, for '%s' (the download URL may require authentication or has expired).",
        basename(out)), call. = FALSE)
    stop(sprintf("%s mismatch for '%s' (expected %s). File left at %s for inspection.",
                 toupper(algo), basename(out), hash, out), call. = FALSE)
  }
  hok
}

# Normalise a figshare article's file list to list(name, url, hash, size) rows.
.pio_figshare_files <- function(meta) {
  lapply(.pio_or(meta$files, list()), function(e) list(
    name = e$name, url = e$download_url,
    hash = .pio_or(e$computed_md5, e$supplied_md5), size = e$size))
}

# Normalise a Zenodo record's file list, handling both the legacy array shape
# and the InvenioRDM files$entries object shape.
.pio_zenodo_files <- function(meta, record_id, api_url, www_url) {
  f <- meta$files
  if (is.null(f)) return(list())
  strip <- function(x) if (is.null(x)) x else sub("^md5:", "", x)
  if (!is.null(f$entries)) {                              # InvenioRDM shape
    nms <- names(f$entries)
    return(lapply(nms, function(nm) {
      e <- f$entries[[nm]]
      url <- .pio_or(e$links$content,
                     sprintf("%s/records/%s/files/%s/content",
                             api_url, record_id, utils::URLencode(nm, reserved = TRUE)))
      list(name = nm, url = url, hash = strip(e$checksum), size = e$size)
    }))
  }
  lapply(f, function(e) {                                 # legacy array shape
    nm <- e$key
    url <- .pio_or(e$links$self,
                   sprintf("%s/records/%s/files/%s?download=1",
                           www_url, record_id, utils::URLencode(nm, reserved = TRUE)))
    list(name = nm, url = url, hash = strip(e$checksum), size = e$size)
  })
}

# Normalise a Mendeley Data file list to list(name, url, hash, size) rows.
.pio_mendeley_files <- function(files) {
  lapply(files, function(f) list(
    name = f$filename, url = f$content_details$download_url,
    hash = f$content_details$sha256_hash, size = f$content_details$size))
}

# Strip a Mendeley DOI (10.17632/<id>.<v>) or data.mendeley.com URL to the bare
# dataset id.
.pio_mendeley_id <- function(x) {
  x <- as.character(x)[1]
  x <- sub("^.*10\\.17632/", "", x)                       # DOI form
  x <- sub("^.*mendeley\\.com/datasets/", "", x)          # URL form
  sub("[/.].*$", "", x)                                   # drop version/path
}

# Resolve a Mendeley dataset version: the given one, or the latest (from the
# public dataset metadata) when NULL.
.pio_mendeley_version <- function(id, version, api_url) {
  if (!is.null(version) && length(version) && !is.na(version[1]))
    return(as.integer(version[1]))
  meta <- .pio_fetch_json(sprintf("%s/datasets/%s", api_url, id))
  v <- .pio_or(meta$version, NA)
  if (is.na(v))
    stop(sprintf("Could not resolve the latest version for Mendeley dataset %s.", id),
         call. = FALSE)
  as.integer(v)
}

# Shared file-loop: filter by name, download each, assemble the result frame.
.pio_download_entries <- function(entries, dest, files, verify, overwrite, quiet,
                                  what, algo = "md5", headers = NULL) {
  if (!is.null(files)) entries <- Filter(function(e) e$name %in% files, entries)
  if (length(entries) == 0L)
    stop(sprintf("%s: no%s files to download.", what,
                 if (is.null(files)) "" else " matching"), call. = FALSE)
  rows <- lapply(entries, function(e) {
    out <- file.path(dest, basename(e$name))
    ok <- .pio_download_file(e$url, out, hash = e$hash, algo = algo, verify = verify,
                             overwrite = overwrite, quiet = quiet, headers = headers)
    data.frame(name = e$name, path = out,
               size = as.numeric(.pio_or(e$size, NA_real_)),
               checksum = .pio_or(e$hash, NA_character_), algo = algo,
               checksum_ok = ok, stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# ---- figshare ---------------------------------------------------------------

#' Download files from a public figshare article
#'
#' Downloads the files attached to a public figshare *article* into `dest` via
#' the figshare public REST API, optionally verifying each file against the MD5
#' checksum figshare reports. No authentication is used, so only public
#' (published) articles are reachable.
#'
#' The `article_id` is the numeric identifier of a figshare article -- the
#' trailing number of a figshare DOI or URL (e.g. `7636887` in
#' `10.6084/m9.figshare.7636887`). For a figshare *collection* (DOI
#' `...figshare.c.<id>`), list its member articles first with
#' [figshareCollectionArticles()] and call this function on each.
#'
#' @param article_id figshare article ID (numeric or character).
#' @param dest Destination directory (created if needed). Default `"."`.
#' @param files Optional character vector of file names; restricts the download
#'   to those files (default `NULL` = every file in the article).
#' @param version Optional integer article version; `NULL` (default) fetches the
#'   latest public version.
#' @param verify_md5 Logical; if `TRUE` (default) each file is checked against
#'   the figshare MD5 and a mismatch is an error.
#' @param overwrite Logical; re-download files already present in `dest`
#'   (default `FALSE`; an existing file with a known-bad checksum is still
#'   re-downloaded).
#' @param quiet Logical; suppress the per-file download progress (default
#'   `TRUE`).
#' @param api_url figshare REST API base URL.
#' @return A data frame (one row per file) with columns `name`, `path`, `size`,
#'   `checksum`, `algo` (`"md5"`) and `checksum_ok` (`TRUE`/`FALSE`, or `NA`
#'   when no checksum was available), invisibly.
#' @seealso [downloadZenodo()], [downloadMendeley()], [downloadFromDOI()],
#'   [figshareCollectionArticles()], [downloadPhysioNet()]
#' @export
#' @examples
#' \dontrun{
#' # Download every file of a figshare article into a temporary directory
#' info <- downloadFigshare(7636887, dest = tempdir())
#' info$path
#' }
downloadFigshare <- function(article_id, dest = ".", files = NULL,
                             version = NULL, verify_md5 = TRUE,
                             overwrite = FALSE, quiet = TRUE,
                             api_url = "https://api.figshare.com/v2") {
  stopifnot(length(article_id) == 1L)
  article_id <- sub("\\.v[0-9]+$", "", as.character(article_id))
  article_id <- sub("^.*figshare\\.(c\\.)?", "", article_id)   # tolerate a full DOI/URL
  if (!dir.exists(dest)) dir.create(dest, recursive = TRUE)
  meta_url <- if (is.null(version))
    sprintf("%s/articles/%s", api_url, article_id)
  else
    sprintf("%s/articles/%s/versions/%s", api_url, article_id, version)
  meta <- .pio_fetch_json(meta_url)
  entries <- .pio_figshare_files(meta)
  if (length(entries) == 0L)
    stop(sprintf(
      "figshare article %s reports no files (private, embargoed, or wrong ID?).",
      article_id), call. = FALSE)
  invisible(.pio_download_entries(entries, dest, files, verify_md5, overwrite,
                                  quiet, sprintf("figshare article %s", article_id),
                                  algo = "md5"))
}

#' List the articles in a public figshare collection
#'
#' Returns the articles that make up a public figshare *collection* (DOI
#' `10.6084/m9.figshare.c.<id>`), so each can be fetched with
#' [downloadFigshare()]. Collections (e.g. GaitRec, `c.4788012`) bundle several
#' articles; figshare has no single-call "download the whole collection", so the
#' idiom is list-then-download-per-article.
#'
#' @param collection_id figshare collection ID (numeric or character); a full
#'   collection DOI/URL is also tolerated.
#' @param api_url figshare REST API base URL.
#' @return A data frame with columns `article_id`, `title` and `doi`, one row
#'   per article (up to the API page-size cap of 1000).
#' @seealso [downloadFigshare()]
#' @export
#' @examples
#' \dontrun{
#' arts <- figshareCollectionArticles(4788012)   # GaitRec
#' downloadFigshare(arts$article_id[1], dest = tempdir())
#' }
figshareCollectionArticles <- function(collection_id,
                                       api_url = "https://api.figshare.com/v2") {
  collection_id <- sub("\\.v[0-9]+$", "", as.character(collection_id))
  collection_id <- sub("^.*figshare\\.c\\.", "", collection_id)
  arts <- .pio_fetch_json(sprintf("%s/collections/%s/articles?page_size=1000",
                                  api_url, collection_id))
  if (length(arts) == 0L)
    stop(sprintf("figshare collection %s reports no articles (wrong ID?).",
                 collection_id), call. = FALSE)
  data.frame(
    article_id = vapply(arts, function(a) as.character(.pio_or(a$id, NA)), ""),
    title      = vapply(arts, function(a) .pio_or(a$title, NA_character_), ""),
    doi        = vapply(arts, function(a) .pio_or(a$doi, NA_character_), ""),
    stringsAsFactors = FALSE)
}

# ---- Zenodo -----------------------------------------------------------------

#' Download files from a public Zenodo record
#'
#' Downloads the files of a public Zenodo *record* into `dest` via the Zenodo
#' public REST API, optionally verifying each file against the MD5 checksum
#' Zenodo reports. No authentication is used, so only open/public records are
#' reachable. Both the legacy file-array response and the newer InvenioRDM
#' `files.entries` response are handled.
#'
#' The `record_id` is the numeric identifier of a Zenodo record -- the trailing
#' number of a Zenodo DOI or URL (e.g. `3374790` in `10.5281/zenodo.3374790`).
#' Note that a Zenodo *concept* DOI resolves to the latest version; pass a
#' specific version's record ID to pin a version.
#'
#' @param record_id Zenodo record ID (numeric or character).
#' @param dest Destination directory (created if needed). Default `"."`.
#' @param files Optional character vector of file names; restricts the download
#'   to those files (default `NULL` = every file in the record).
#' @param verify_md5 Logical; if `TRUE` (default) each file is checked against
#'   the Zenodo MD5 and a mismatch is an error.
#' @param overwrite Logical; re-download files already present in `dest`
#'   (default `FALSE`; an existing file with a known-bad checksum is still
#'   re-downloaded).
#' @param quiet Logical; suppress the per-file download progress (default
#'   `TRUE`).
#' @param api_url Zenodo REST API base URL.
#' @return A data frame (one row per file) with columns `name`, `path`, `size`,
#'   `checksum`, `algo` (`"md5"`) and `checksum_ok` (`TRUE`/`FALSE`, or `NA`
#'   when no checksum was available), invisibly.
#' @seealso [downloadFigshare()], [downloadMendeley()], [downloadFromDOI()],
#'   [downloadPhysioNet()]
#' @export
#' @examples
#' \dontrun{
#' info <- downloadZenodo(3374790, dest = tempdir())
#' info$path
#' }
downloadZenodo <- function(record_id, dest = ".", files = NULL,
                           verify_md5 = TRUE, overwrite = FALSE, quiet = TRUE,
                           api_url = "https://zenodo.org/api") {
  stopifnot(length(record_id) == 1L)
  record_id <- sub("^.*zenodo\\.", "", as.character(record_id))   # tolerate a full DOI/URL
  if (!dir.exists(dest)) dir.create(dest, recursive = TRUE)
  www_url <- sub("/api/?$", "", api_url)
  meta <- .pio_fetch_json(sprintf("%s/records/%s", api_url, record_id))
  entries <- .pio_zenodo_files(meta, record_id, api_url, www_url)
  if (length(entries) == 0L)
    stop(sprintf(
      "Zenodo record %s reports no files (restricted, embargoed, or wrong ID?).",
      record_id), call. = FALSE)
  invisible(.pio_download_entries(entries, dest, files, verify_md5, overwrite,
                                  quiet, sprintf("Zenodo record %s", record_id),
                                  algo = "md5"))
}

# ---- Mendeley Data ----------------------------------------------------------

#' List the files of a public Mendeley Data dataset
#'
#' Returns the public file manifest of a Mendeley Data dataset -- file names,
#' sizes, SHA-256 hashes and content ids -- via the Mendeley Data public REST
#' API. This metadata is available **without authentication**; downloading the
#' file *bytes*, however, requires an OAuth token (see [downloadMendeley()]).
#'
#' The `dataset_id` is the Mendeley Data dataset identifier -- the alphanumeric
#' component of a Mendeley DOI `10.17632/<id>.<version>` or a
#' `data.mendeley.com/datasets/<id>/<version>` URL (both are tolerated).
#'
#' @param dataset_id Mendeley dataset id (or a full DOI/URL).
#' @param version Optional integer dataset version; `NULL` (default) resolves to
#'   the latest published version.
#' @param folder_id Folder to list (default `"root"`; Mendeley organises files
#'   into folders and only one folder level is listed per call).
#' @param api_url Mendeley Data public API base URL.
#' @return A data frame with columns `name`, `size`, `sha256`, `content_id` and
#'   `version`, one row per file.
#' @seealso [downloadMendeley()], [downloadFromDOI()]
#' @export
#' @examples
#' \dontrun{
#' files <- mendeleyDatasetFiles("mzpz22x58x")   # latest version
#' files[, c("name", "size", "sha256")]
#' }
mendeleyDatasetFiles <- function(dataset_id, version = NULL, folder_id = "root",
                                 api_url = "https://data.mendeley.com/public-api") {
  dataset_id <- .pio_mendeley_id(dataset_id)
  version <- .pio_mendeley_version(dataset_id, version, api_url)
  files <- .pio_fetch_json(sprintf("%s/datasets/%s/files?folder_id=%s&version=%s",
                                   api_url, dataset_id, folder_id, version))
  if (length(files) == 0L)
    stop(sprintf("Mendeley dataset %s (v%s) reports no files in folder '%s'.",
                 dataset_id, version, folder_id), call. = FALSE)
  data.frame(
    name       = vapply(files, function(f) .pio_or(f$filename, NA_character_), ""),
    size       = vapply(files, function(f) as.numeric(.pio_or(f$content_details$size, NA)), 0),
    sha256     = vapply(files, function(f) .pio_or(f$content_details$sha256_hash, NA_character_), ""),
    content_id = vapply(files, function(f) .pio_or(f$id, NA_character_), ""),
    version    = version,
    stringsAsFactors = FALSE)
}

#' Download files from a Mendeley Data dataset
#'
#' Downloads the files of a Mendeley Data dataset into `dest`, verifying each
#' against the SHA-256 hash Mendeley reports.
#'
#' Unlike figshare and Zenodo, Mendeley Data exposes dataset and file
#' *metadata* publicly (see [mendeleyDatasetFiles()]) but requires an **OAuth
#' access token** to download the file *bytes*. Supply the token via
#' `access_token` or the `MENDELEY_TOKEN` environment variable; obtain one
#' through the Mendeley Data API (an OAuth2 application). Without a token this
#' function errors early and points you at [mendeleyDatasetFiles()] for the
#' public manifest.
#'
#' The `dataset_id` is the Mendeley Data identifier -- the alphanumeric part of
#' a Mendeley DOI `10.17632/<id>.<version>` or a
#' `data.mendeley.com/datasets/<id>/<version>` URL.
#'
#' @param dataset_id Mendeley dataset id (or a full DOI/URL).
#' @param dest Destination directory (created if needed). Default `"."`.
#' @param files Optional character vector of file names; restricts the download
#'   to those files (default `NULL` = every file in the folder).
#' @param version Optional integer dataset version; `NULL` (default) resolves to
#'   the latest published version.
#' @param access_token Mendeley OAuth bearer token; defaults to the
#'   `MENDELEY_TOKEN` environment variable. Required to download file bytes.
#' @param verify_hash Logical; if `TRUE` (default) each file is checked against
#'   the Mendeley SHA-256 and a mismatch is an error.
#' @param overwrite Logical; re-download files already present in `dest`
#'   (default `FALSE`).
#' @param quiet Logical; suppress the per-file download progress (default
#'   `TRUE`).
#' @param folder_id Folder to download from (default `"root"`).
#' @param api_url Mendeley Data public API base URL.
#' @return A data frame (one row per file) with columns `name`, `path`, `size`,
#'   `checksum`, `algo` (`"sha256"`) and `checksum_ok`, invisibly.
#' @seealso [mendeleyDatasetFiles()], [downloadFigshare()], [downloadZenodo()],
#'   [downloadFromDOI()]
#' @export
#' @examples
#' \dontrun{
#' # metadata is public:
#' mendeleyDatasetFiles("mzpz22x58x")
#' # bytes need a token:
#' downloadMendeley("mzpz22x58x", dest = tempdir(),
#'                  access_token = Sys.getenv("MENDELEY_TOKEN"))
#' }
downloadMendeley <- function(dataset_id, dest = ".", files = NULL, version = NULL,
                             access_token = Sys.getenv("MENDELEY_TOKEN", ""),
                             verify_hash = TRUE, overwrite = FALSE, quiet = TRUE,
                             folder_id = "root",
                             api_url = "https://data.mendeley.com/public-api") {
  stopifnot(length(dataset_id) == 1L)
  dataset_id <- .pio_mendeley_id(dataset_id)
  if (is.null(access_token) || length(access_token) == 0L) access_token <- ""
  access_token <- as.character(access_token)[1]
  if (is.na(access_token) || !nzchar(access_token))
    stop("downloadMendeley: Mendeley Data requires an OAuth access token to download file ",
         "bytes (the dataset and file metadata are public, the file contents are not). Pass ",
         "access_token= or set the MENDELEY_TOKEN environment variable (obtain a token via the ",
         "Mendeley Data API / an OAuth2 application). The public file manifest -- names, sizes, ",
         "SHA-256 hashes -- is available without a token via mendeleyDatasetFiles().",
         call. = FALSE)
  if (!dir.exists(dest)) dir.create(dest, recursive = TRUE)
  version <- .pio_mendeley_version(dataset_id, version, api_url)
  raw <- .pio_fetch_json(sprintf("%s/datasets/%s/files?folder_id=%s&version=%s",
                                 api_url, dataset_id, folder_id, version))
  entries <- .pio_mendeley_files(raw)
  if (length(entries) == 0L)
    stop(sprintf("Mendeley dataset %s (v%s) reports no files in folder '%s'.",
                 dataset_id, version, folder_id), call. = FALSE)
  hdr <- c(Authorization = paste("Bearer", access_token))
  invisible(.pio_download_entries(entries, dest, files, verify_hash, overwrite, quiet,
                                  sprintf("Mendeley dataset %s (v%s)", dataset_id, version),
                                  algo = "sha256", headers = hdr))
}

# ---- DOI dispatcher ---------------------------------------------------------

#' Download a dataset from its DOI (figshare, Zenodo or Mendeley Data)
#'
#' Convenience dispatcher: routes a figshare, Zenodo or Mendeley Data DOI (or
#' the bare `doi.org` URL) to [downloadFigshare()], [downloadZenodo()] or
#' [downloadMendeley()]. A figshare *collection* DOI is rejected with a pointer
#' to [figshareCollectionArticles()].
#'
#' @param doi A DOI such as `10.6084/m9.figshare.7636887` (figshare),
#'   `10.5281/zenodo.3374790` (Zenodo) or `10.17632/mzpz22x58x.3` (Mendeley
#'   Data), optionally as a full `https://doi.org/...` URL.
#' @param dest Destination directory (created if needed). Default `"."`.
#' @param ... Passed to the underlying downloader (e.g. `files`, `verify_md5`,
#'   `overwrite`, `quiet`; `access_token` for Mendeley).
#' @return The download-info data frame from the underlying function, invisibly.
#' @seealso [downloadFigshare()], [downloadZenodo()], [downloadMendeley()],
#'   [figshareCollectionArticles()]
#' @export
#' @examples
#' \dontrun{
#' downloadFromDOI("10.5281/zenodo.3374790", dest = tempdir())
#' }
downloadFromDOI <- function(doi, dest = ".", ...) {
  stopifnot(length(doi) == 1L)
  d <- tolower(trimws(doi))
  d <- sub("^https?://(dx\\.)?doi\\.org/", "", d)
  if (grepl("figshare\\.c\\.", d))
    stop("This is a figshare COLLECTION DOI. List its member articles with ",
         "figshareCollectionArticles() and download each with downloadFigshare().",
         call. = FALSE)
  if (grepl("figshare", d)) {
    id <- sub("\\.v[0-9]+$", "", sub("^.*figshare\\.", "", d))
    return(invisible(downloadFigshare(id, dest = dest, ...)))
  }
  if (grepl("zenodo", d)) {
    id <- sub("^.*zenodo\\.", "", d)
    return(invisible(downloadZenodo(id, dest = dest, ...)))
  }
  if (grepl("10\\.17632/", d) || grepl("mendeley", d)) {
    rest <- sub("^.*10\\.17632/", "", d)             # <id>.<version>
    id <- sub("\\.[0-9]+$", "", rest)
    vtail <- sub("^.*\\.", "", rest)
    ver <- if (grepl("^[0-9]+$", vtail)) as.integer(vtail) else NULL
    return(invisible(downloadMendeley(id, dest = dest, version = ver, ...)))
  }
  stop(sprintf(
    "Unsupported DOI '%s': only figshare (10.6084/m9.figshare.*), Zenodo (10.5281/zenodo.*) and Mendeley Data (10.17632/*) are supported.",
    doi), call. = FALSE)
}
