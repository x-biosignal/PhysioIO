library(testthat)
library(PhysioIO)

# ---- offline: metadata normalisers (real API shapes, synthetic payloads) ----

test_that(".pio_figshare_files extracts name/url/hash/size from an article payload", {
  meta <- list(files = list(
    list(name = "a.csv", download_url = "https://ndownloader.figshare.com/files/111",
         computed_md5 = "abc", supplied_md5 = "abc", size = 10),
    list(name = "b.dat", download_url = "https://ndownloader.figshare.com/files/222",
         computed_md5 = "def", size = 20)))
  e <- PhysioIO:::.pio_figshare_files(meta)
  expect_length(e, 2L)
  expect_identical(e[[1]]$name, "a.csv")
  expect_identical(e[[1]]$url, "https://ndownloader.figshare.com/files/111")
  expect_identical(e[[1]]$hash, "abc")
  expect_identical(e[[2]]$size, 20)
})

test_that(".pio_zenodo_files handles the legacy file-array shape and strips 'md5:'", {
  meta <- list(files = list(
    list(key = "x.txt", size = 715, checksum = "md5:5837ed87",
         links = list(self = "https://zenodo.org/api/files/BUCKET/x.txt"))))
  e <- PhysioIO:::.pio_zenodo_files(meta, "123", "https://zenodo.org/api",
                                    "https://zenodo.org")
  expect_length(e, 1L)
  expect_identical(e[[1]]$name, "x.txt")
  expect_identical(e[[1]]$url, "https://zenodo.org/api/files/BUCKET/x.txt")
  expect_identical(e[[1]]$hash, "5837ed87")          # 'md5:' prefix stripped
  expect_identical(e[[1]]$size, 715)
})

test_that(".pio_zenodo_files handles the InvenioRDM files$entries shape", {
  meta1 <- list(files = list(entries = list(
    "y.bin" = list(size = 5, checksum = "md5:deadbeef",
      links = list(content = "https://zenodo.org/api/records/9/files/y.bin/content")))))
  e1 <- PhysioIO:::.pio_zenodo_files(meta1, "9", "https://zenodo.org/api",
                                     "https://zenodo.org")
  expect_identical(e1[[1]]$name, "y.bin")
  expect_identical(e1[[1]]$url, "https://zenodo.org/api/records/9/files/y.bin/content")
  expect_identical(e1[[1]]$hash, "deadbeef")

  meta2 <- list(files = list(entries = list(
    "z q.bin" = list(size = 3, checksum = "md5:cafe", links = list()))))
  e2 <- PhysioIO:::.pio_zenodo_files(meta2, "9", "https://zenodo.org/api",
                                     "https://zenodo.org")
  expect_identical(e2[[1]]$url,
                   "https://zenodo.org/api/records/9/files/z%20q.bin/content")
})

test_that(".pio_mendeley_files extracts name/url/hash(sha256)/size", {
  files <- list(
    list(filename = "a.csv", id = "fid1",
         content_details = list(size = 10, sha256_hash = "abc",
           download_url = "https://data.mendeley.com/public-files/x/files/fid1/file_downloaded")),
    list(filename = "b.zip", id = "fid2",
         content_details = list(size = 99, sha256_hash = "def",
           download_url = "https://data.mendeley.com/public-files/x/files/fid2/file_downloaded")))
  e <- PhysioIO:::.pio_mendeley_files(files)
  expect_length(e, 2L)
  expect_identical(e[[1]]$name, "a.csv")
  expect_identical(e[[1]]$hash, "abc")
  expect_identical(e[[2]]$size, 99)
  expect_match(e[[1]]$url, "file_downloaded$")
})

test_that(".pio_mendeley_id strips DOI and URL forms to the bare id", {
  expect_identical(PhysioIO:::.pio_mendeley_id("mzpz22x58x"), "mzpz22x58x")
  expect_identical(PhysioIO:::.pio_mendeley_id("10.17632/mzpz22x58x.3"), "mzpz22x58x")
  expect_identical(PhysioIO:::.pio_mendeley_id("https://doi.org/10.17632/mzpz22x58x.3"),
                   "mzpz22x58x")
  expect_identical(PhysioIO:::.pio_mendeley_id("https://data.mendeley.com/datasets/mzpz22x58x/3"),
                   "mzpz22x58x")
})

test_that(".pio_or returns the fallback for NULL/empty", {
  expect_identical(PhysioIO:::.pio_or(NULL, "fb"), "fb")
  expect_identical(PhysioIO:::.pio_or(list(), 7), 7)
  expect_identical(PhysioIO:::.pio_or("x", "fb"), "x")
})

# ---- offline: error-page detection (auth/expiry served with HTTP 200) -------

test_that(".pio_download_file flags an error-page body served in place of a file", {
  src <- tempfile(fileext = ".json"); writeLines('{"error":404}', src)
  out <- tempfile()
  msg <- tryCatch(
    PhysioIO:::.pio_download_file(paste0("file://", normalizePath(src)), out,
                                 hash = "00", algo = "sha256", overwrite = TRUE),
    error = function(e) conditionMessage(e))
  if (grepl("Download failed", msg)) skip("file:// scheme not supported by download.file here")
  expect_match(msg, "error page")
})

# ---- offline: DOI dispatcher routing (errors before any network call) -------

test_that("downloadFromDOI rejects a figshare COLLECTION DOI with guidance", {
  expect_error(downloadFromDOI("10.6084/m9.figshare.c.4788012.v1"), "COLLECTION")
})

test_that("downloadFromDOI rejects an unsupported DOI", {
  expect_error(downloadFromDOI("10.1234/not.a.repo.999"), "Unsupported")
})

test_that("downloadMendeley without a token errors with guidance (before any network)", {
  expect_error(downloadMendeley("mzpz22x58x", access_token = ""), "access token")
})

test_that("downloadFromDOI routes a Mendeley DOI to downloadMendeley", {
  # routed to Mendeley, which demands a token -> proves routing, still offline
  expect_error(downloadFromDOI("10.17632/mzpz22x58x.3", access_token = ""),
               "access token")
})

# ---- live: figshare (stable GaitRec collection member, 7 KB, known MD5) -----

test_that("downloadFigshare fetches and MD5-verifies a real figshare file", {
  skip_on_cran()
  skip_if_offline()
  dd <- file.path(tempdir(), "pio-figshare-test")
  unlink(dd, recursive = TRUE); dir.create(dd)
  info <- tryCatch(
    downloadFigshare(11394852, dest = dd, files = "data_import.ipynb"),
    error = function(e) skip(paste("figshare unreachable:", conditionMessage(e))))
  expect_s3_class(info, "data.frame")
  expect_equal(nrow(info), 1L)
  expect_identical(info$name, "data_import.ipynb")
  expect_true(file.exists(info$path))
  expect_equal(as.numeric(file.info(info$path)$size), 7332)
  expect_identical(info$algo, "md5")
  expect_identical(info$checksum, "6408b0ef17d9e2ce08dbb82737d3bee4")
  expect_true(isTRUE(info$checksum_ok))
})

test_that("figshareCollectionArticles lists the GaitRec collection's articles", {
  skip_on_cran()
  skip_if_offline()
  arts <- tryCatch(figshareCollectionArticles(4788012),
    error = function(e) skip(paste("figshare unreachable:", conditionMessage(e))))
  expect_s3_class(arts, "data.frame")
  expect_true(all(c("article_id", "title", "doi") %in% names(arts)))
  expect_true("11394852" %in% arts$article_id)
})

test_that("downloadFromDOI routes a full doi.org figshare URL to downloadFigshare", {
  skip_on_cran()
  skip_if_offline()
  dd <- file.path(tempdir(), "pio-doi-test")
  unlink(dd, recursive = TRUE); dir.create(dd)
  info <- tryCatch(
    downloadFromDOI("https://doi.org/10.6084/m9.figshare.11394852",
                    dest = dd, files = "data_import.ipynb"),
    error = function(e) skip(paste("figshare unreachable:", conditionMessage(e))))
  expect_identical(info$name, "data_import.ipynb")
  expect_true(isTRUE(info$checksum_ok))
})

# ---- live: Zenodo (self-consistent: verify against the MD5 Zenodo reports) --

test_that("downloadZenodo fetches and MD5-verifies a real Zenodo file", {
  skip_on_cran()
  skip_if_offline()
  dd <- file.path(tempdir(), "pio-zenodo-test")
  unlink(dd, recursive = TRUE); dir.create(dd)
  info <- tryCatch(
    downloadZenodo(22659076, dest = dd, files = "SHA256SUMS.txt"),
    error = function(e) skip(paste("zenodo unreachable:", conditionMessage(e))))
  expect_s3_class(info, "data.frame")
  expect_equal(nrow(info), 1L)
  expect_true(file.exists(info$path))
  expect_true(info$size > 0)
  expect_identical(info$algo, "md5")
  expect_true(isTRUE(info$checksum_ok))   # matched the MD5 Zenodo itself reported
})

# ---- live: Mendeley Data (public manifest; download bytes need a token) -----

test_that("mendeleyDatasetFiles returns a public SHA-256 manifest without auth", {
  skip_on_cran()
  skip_if_offline()
  df <- tryCatch(mendeleyDatasetFiles("mzpz22x58x", version = 3),
    error = function(e) skip(paste("mendeley unreachable:", conditionMessage(e))))
  expect_s3_class(df, "data.frame")
  expect_true(all(c("name", "size", "sha256", "content_id", "version") %in% names(df)))
  i <- which(df$name == "README.md")
  expect_length(i, 1L)
  expect_equal(df$size[i], 278)
  expect_identical(df$sha256[i],
                   "6afa5d459d55be1b5a699ff1d389b46ffdb5dcd9093ec1396e25c3acdfb15b9b")
  expect_equal(unique(df$version), 3)
})

test_that("mendeleyDatasetFiles resolves the latest version when version = NULL", {
  skip_on_cran()
  skip_if_offline()
  df <- tryCatch(mendeleyDatasetFiles("mzpz22x58x"),
    error = function(e) skip(paste("mendeley unreachable:", conditionMessage(e))))
  expect_true(unique(df$version) >= 3)   # latest published version is >= the known v3
})
