# reticulate / MNE-Python bridge for PhysioExperiment objects
#
# toMNE()   : PhysioExperiment -> mne.io.RawArray (info + montage + annotations)
# fromMNE() : mne.io.RawArray  -> PhysioExperiment (+ provenance record)
#
# MNE is an OPTIONAL backend reached through the Python 'mne' module via
# reticulate; every entry point guards on hasMNE().

# Channel types MNE-Python accepts; anything else maps to "misc".
.MNE_CH_TYPES <- c("eeg", "meg", "mag", "grad", "ref_meg", "ecg", "emg", "eog",
                   "seeg", "ecog", "dbs", "bio", "stim", "resp", "gsr",
                   "temperature", "eyegaze", "pupil", "misc")

# Delimiter (ASCII unit separator) that packs a PhysioEvents type + value into
# a single MNE annotation description so both survive the round-trip.
.MNE_EVENT_SEP <- "\u001f"

#' Is the Python \pkg{mne} module available?
#'
#' @return \code{TRUE} if \pkg{reticulate} and the Python \code{mne} module are
#'   both available, otherwise \code{FALSE}.
#' @seealso [pyMNEVersion()], [toMNE()], [fromMNE()]
#' @export
#' @examples
#' hasMNE()
hasMNE <- function() {
  requireNamespace("reticulate", quietly = TRUE) &&
    isTRUE(tryCatch(reticulate::py_module_available("mne"),
                    error = function(e) FALSE))
}

#' Version of the available Python \pkg{mne} module
#'
#' @return The \code{mne.__version__} string, or \code{NA_character_} when
#'   \pkg{mne} is not available.
#' @seealso [hasMNE()]
#' @export
#' @examples
#' pyMNEVersion()
pyMNEVersion <- function() {
  if (!hasMNE()) return(NA_character_)
  mne <- reticulate::import("mne", delay_load = TRUE)
  as.character(reticulate::py_to_r(mne$`__version__`))
}

.need_mne <- function() {
  if (!hasMNE()) {
    stop("The Python 'mne' module (via reticulate) is required. ",
         "Install it with reticulate::py_install('mne').", call. = FALSE)
  }
}

.to_mne_ch_type <- function(types) {
  t <- tolower(as.character(types))
  ifelse(t %in% .MNE_CH_TYPES, t, "misc")
}

#' Convert a PhysioExperiment to an MNE-Python RawArray
#'
#' Builds an \code{mne.io.RawArray} from a \code{PhysioExperiment}: channel
#' names, channel types and sampling rate populate the \code{mne.Info}; any
#' electrode positions (\code{getElectrodePositions()}) become a
#' \code{DigMontage}; and any events (\code{getEvents()}) become
#' \code{mne.Annotations}. The signal matrix is passed through unchanged, so
#' \code{fromMNE(toMNE(x))} reproduces it exactly.
#'
#' Channel types not recognised by MNE are mapped to \code{"misc"} (and are
#' lower-cased to MNE's convention). Channel names must be unique. An event's
#' \code{type} and (when present) \code{value} are packed into the annotation
#' description so both survive the round-trip; a missing (\code{NA}) value
#' becomes \code{""} because MNE annotations cannot represent \code{NA}. Events
#' whose onset falls outside the recording are dropped by MNE (with a warning).
#'
#' @param x A \code{PhysioExperiment}.
#' @param assay Assay to export (default: the object's default assay).
#' @return An \code{mne.io.RawArray} Python object.
#' @references
#'   Gramfort A, et al. (2013). "MEG and EEG data analysis with MNE-Python."
#'   Frontiers in Neuroscience, 7, 267.
#' @seealso [fromMNE()], [hasMNE()]
#' @export
#' @examples
#' if (hasMNE()) {
#'   pe <- PhysioExperiment(
#'     assays = S4Vectors::SimpleList(raw = matrix(rnorm(300), 100, 3)),
#'     colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz"),
#'                                    type = rep("eeg", 3)),
#'     samplingRate = 100)
#'   raw <- toMNE(pe)
#' }
toMNE <- function(x, assay = NULL) {
  stopifnot(inherits(x, "PhysioExperiment"))
  .need_mne()
  mne <- reticulate::import("mne", delay_load = TRUE)
  np <- reticulate::import("numpy", delay_load = TRUE)

  if (is.null(assay)) assay <- defaultAssay(x)
  data <- as.matrix(SummarizedExperiment::assay(x, assay))  # nsamp x nchan
  storage.mode(data) <- "double"
  n_ch <- ncol(data)

  ch_names <- channelNames(x)
  if (is.null(ch_names) || length(ch_names) != n_ch) {
    ch_names <- paste0("ch", seq_len(n_ch))
  }
  ch_names <- as.character(ch_names)
  # MNE keys channels (and montage positions) by name, so duplicates would
  # silently collide and drop positions.
  if (anyDuplicated(ch_names)) {
    stop("toMNE requires unique channel names; duplicated: ",
         paste(unique(ch_names[duplicated(ch_names)]), collapse = ", "),
         call. = FALSE)
  }

  cd <- SummarizedExperiment::colData(x)
  types <- if ("type" %in% names(cd)) as.character(cd$type) else rep("misc", n_ch)
  ch_types <- .to_mne_ch_type(types)

  sfreq <- as.numeric(samplingRate(x))[1]
  if (length(sfreq) != 1 || is.na(sfreq) || sfreq <= 0) {
    stop("samplingRate(x) must be a single positive value to build an MNE ",
         "object (MNE cannot represent an unknown sampling rate).",
         call. = FALSE)
  }

  info <- mne$create_info(ch_names = as.list(ch_names),
                          sfreq = sfreq,
                          ch_types = as.list(ch_types))
  raw <- mne$io$RawArray(np$array(t(data)), info, verbose = FALSE)

  # Montage from electrode positions (metres, head frame).
  pos <- tryCatch(getElectrodePositions(x), error = function(e) NULL)
  if (!is.null(pos) && all(c("x", "y", "z") %in% names(pos))) {
    ok <- !(is.na(pos$x) | is.na(pos$y) | is.na(pos$z))
    if (any(ok)) {
      ch_pos <- stats::setNames(
        lapply(which(ok), function(i) np$array(c(pos$x[i], pos$y[i], pos$z[i]))),
        ch_names[ok])
      mont <- mne$channels$make_dig_montage(ch_pos = reticulate::dict(ch_pos),
                                            coord_frame = "head")
      raw$set_montage(mont, on_missing = "ignore", verbose = FALSE)
    }
  }

  # Annotations from events.
  ev <- tryCatch(getEvents(x), error = function(e) NULL)
  if (!is.null(ev) && nEvents(ev) > 0) {
    edf <- ev@events
    # MNE drops annotations whose onset falls outside the data range; warn so the
    # loss is not silent.
    duration_s <- nrow(data) / sfreq
    n_out <- sum(edf$onset < 0 | edf$onset >= duration_s, na.rm = TRUE)
    if (n_out > 0) {
      warning(sprintf(paste0("%d event(s) fall outside the %.3fs recording and ",
                             "will be dropped by MNE."), n_out, duration_s),
              call. = FALSE)
    }
    typ <- as.character(edf$type)
    # MNE annotation descriptions cannot represent NA, so a missing value is
    # normalised to "" (it returns as "" on import).
    val <- as.character(edf$value)
    val[is.na(val)] <- ""
    desc <- ifelse(nzchar(val), paste0(typ, .MNE_EVENT_SEP, val), typ)
    ann <- mne$Annotations(onset = as.numeric(edf$onset),
                           duration = as.numeric(edf$duration),
                           description = as.list(desc))
    raw$set_annotations(ann, verbose = FALSE)
  }

  raw
}

#' Convert an MNE-Python Raw object to a PhysioExperiment
#'
#' Inverse of [toMNE()]: reads the signal matrix, channel names/types, sampling
#' rate, electrode montage and annotations from an MNE \code{Raw} object into a
#' \code{PhysioExperiment}. The import is recorded in the object's provenance.
#'
#' @param raw An MNE \code{Raw} object (e.g. from [toMNE()] or
#'   \code{mne.io.read_raw_*}).
#' @return A \code{PhysioExperiment} with the signal in the \code{"raw"} assay.
#' @seealso [toMNE()], [hasMNE()]
#' @export
#' @examples
#' if (hasMNE()) {
#'   pe <- PhysioExperiment(
#'     assays = S4Vectors::SimpleList(raw = matrix(rnorm(300), 100, 3)),
#'     colData = S4Vectors::DataFrame(label = c("Fp1", "Fp2", "Cz"),
#'                                    type = rep("eeg", 3)),
#'     samplingRate = 100)
#'   pe2 <- fromMNE(toMNE(pe))
#' }
fromMNE <- function(raw) {
  .need_mne()

  data <- t(reticulate::py_to_r(raw$get_data()))         # nsamp x nchan
  ch_names <- as.character(reticulate::py_to_r(raw$info$ch_names))
  ch_types <- as.character(reticulate::py_to_r(raw$get_channel_types()))
  sfreq <- as.numeric(reticulate::py_to_r(raw$info$`__getitem__`("sfreq")))[1]
  colnames(data) <- ch_names

  pe <- PhysioExperiment(
    assays = S4Vectors::SimpleList(raw = data),
    colData = S4Vectors::DataFrame(label = ch_names, type = ch_types),
    metadata = list(source_format = "mne"),
    samplingRate = sfreq)

  # Montage -> electrode positions.
  mont <- tryCatch(raw$get_montage(), error = function(e) NULL)
  if (!is.null(mont) && !inherits(mont, "python.builtin.NoneType")) {
    ch_pos <- tryCatch(
      reticulate::py_to_r(mont$get_positions()[["ch_pos"]]),
      error = function(e) NULL)
    if (length(ch_pos) > 0) {
      pmat <- t(vapply(ch_names, function(nm) {
        p <- ch_pos[[nm]]
        if (is.null(p)) c(NA_real_, NA_real_, NA_real_) else as.numeric(p)[1:3]
      }, numeric(3)))
      if (any(!is.na(pmat))) {
        pe <- setElectrodePositions(
          pe, data.frame(x = pmat[, 1], y = pmat[, 2], z = pmat[, 3]))
      }
    }
  }

  # Annotations -> events.
  ann <- raw$annotations
  onset <- as.numeric(reticulate::py_to_r(ann$onset))
  if (length(onset) > 0) {
    # MNE annotation onsets are relative to the measurement start; shift them to
    # be relative to the first data sample (0 for a toMNE RawArray, nonzero for
    # a Raw loaded with first_samp > 0).
    first_time <- as.numeric(reticulate::py_to_r(raw$first_time))[1]
    if (length(first_time) == 1 && !is.na(first_time)) onset <- onset - first_time
    duration <- as.numeric(reticulate::py_to_r(ann$duration))
    desc <- as.character(reticulate::py_to_r(ann$description))
    # Split on the FIRST separator only: type is everything before it, value
    # everything after (so an empty description gives type "", and a value that
    # itself contains the separator is preserved).
    pos <- regexpr(.MNE_EVENT_SEP, desc, fixed = TRUE)
    has_sep <- pos > 0L
    typ <- ifelse(has_sep, substr(desc, 1L, pos - 1L), desc)
    val <- ifelse(has_sep, substr(desc, pos + 1L, nchar(desc)), "")
    pe <- setEvents(pe, PhysioEvents(onset = onset, duration = duration,
                                     type = typ, value = val))
  }

  # Record the import in provenance.
  pe <- logStep(pe, "fromMNE",
                params = list(mne_version = pyMNEVersion(),
                              n_channels = length(ch_names)))
  pe
}
