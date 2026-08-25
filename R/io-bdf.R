# BDF (BioSemi 24-bit) trigger support. The core readBDF()/writeBDF() live in
# io-edf.R (they share the EDF header parser and the DMIO-05 multi-rate assembly
# so differing native rates yield a MultiRatePhysioExperiment for BDF too). This
# file adds extraction of stimulus triggers from the BioSemi "Status" channel,
# whose low 16 bits carry the trigger inputs.

# Read the raw digital values of the "Status" channel of a BDF file. Optionally
# restricted to records start_record..end_record so triggers stay aligned with a
# time-subset read.
.readBDFStatusChannel <- function(path, start_record = 1L, end_record = NULL) {
  con <- file(path, "rb"); on.exit(close(con))
  header <- .parseEDFHeader(con)
  ns <- header$num_signals
  sh <- .parseEDFSignalHeaders(con, ns)
  status_idx <- which(sh$label == "Status")
  if (length(status_idx) == 0L) return(NULL)
  status_idx <- status_idx[1]

  n_records <- header$num_data_records
  spr <- sh$samples_per_record
  fs <- spr[status_idx] / header$data_record_duration
  if (is.null(end_record)) end_record <- n_records
  records_to_read <- end_record - start_record + 1L

  bytes_per_record <- sum(spr * 3L)            # BDF: 3 bytes per sample
  seek(con, 256L * (ns + 1L) + (start_record - 1L) * bytes_per_record)
  vals <- integer(records_to_read * spr[status_idx])
  pos <- 0L
  for (rec in seq_len(records_to_read)) {
    for (sig in seq_len(ns)) {
      nb <- spr[sig] * 3L
      if (sig == status_idx) {
        rb <- readBin(con, "raw", nb)
        vals[(pos + 1L):(pos + spr[sig])] <-
          as.integer(.convert24bitToInteger(rb, spr[sig]))
        pos <- pos + spr[sig]
      } else {
        seek(con, seek(con) + nb)              # skip the other signals
      }
    }
  }
  list(values = vals, fs = fs)
}

#' Read the BioSemi Status channel of a BDF file
#'
#' Returns the raw digital values of the \code{"Status"} channel. The low 16
#' bits of each value are the stimulus trigger inputs.
#'
#' @param path Path to a BDF file.
#' @return A list with \code{values} (integer status words) and \code{fs} (the
#'   Status channel sampling rate), or \code{NULL} if the file has no Status
#'   channel.
#' @seealso \code{\link{bdfTriggerEvents}}, \code{\link{readBDF}}
#' @export
readBDFStatus <- function(path) {
  if (!file.exists(path)) stop("File not found: ", path, call. = FALSE)
  .readBDFStatusChannel(path)
}

#' Extract trigger events from a BioSemi Status channel
#'
#' Detects transitions of the low-16-bit trigger value to a new non-zero code
#' and returns them as a \code{PhysioEvents}: each rising transition is an event
#' whose onset is the transition time (seconds) and whose value is the trigger
#' code.
#'
#' @param status Integer vector of raw Status-channel digital values (as from
#'   \code{\link{readBDFStatus}}).
#' @param sampling_rate Sampling rate of the Status channel in Hz.
#' @return A \code{PhysioEvents} object.
#' @seealso \code{\link{readBDFStatus}}, \code{\link{readBDF}}
#' @export
bdfTriggerEvents <- function(status, sampling_rate) {
  stopifnot(is.numeric(status), is.numeric(sampling_rate), sampling_rate > 0)
  trig <- bitwAnd(as.integer(status), 0xFFFFL)          # low 16 bits
  if (length(trig) == 0L) {
    return(PhysioEvents(onset = numeric(0)))
  }
  prev <- c(0L, trig[-length(trig)])
  onset_idx <- which(trig != prev & trig != 0L)          # rising to a new code
  if (length(onset_idx) == 0L) {
    return(PhysioEvents(onset = numeric(0)))
  }
  PhysioEvents(
    onset = (onset_idx - 1L) / sampling_rate,
    duration = 0,
    type = rep("trigger", length(onset_idx)),
    value = as.character(trig[onset_idx]))
}

# Extract trigger events from a BDF file and attach them to the read object
# (called by readBDF when status = TRUE and a Status channel is present).
.attachBDFTriggers <- function(result, path, start_record = 1L,
                               end_record = NULL) {
  st <- tryCatch(.readBDFStatusChannel(path, start_record, end_record),
                 error = function(e) NULL)
  if (is.null(st) || length(st$values) == 0L) return(result)
  ev <- bdfTriggerEvents(st$values, st$fs)
  if (nEvents(ev) == 0L) return(result)
  if (methods::is(result, "MultiRatePhysioExperiment")) {
    s <- streams(result)
    s[[1]] <- setEvents(s[[1]], ev)
    streams(result) <- s
    result
  } else {
    setEvents(result, ev)
  }
}
