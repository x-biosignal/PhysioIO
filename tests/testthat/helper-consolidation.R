# Shared fixture for the BrainVision/GDF I/O tests.
# Mirrors the shared make_pe_2d() so those tests run unchanged.
make_pe_2d <- function(n_time = 1000, n_channels = 4, sr = 250) {
  data <- matrix(rnorm(n_time * n_channels), nrow = n_time, ncol = n_channels)
  colnames(data) <- paste0("Ch", seq_len(n_channels))

  PhysioExperiment(
    assays = list(raw = data),
    colData = S4Vectors::DataFrame(
      label = paste0("Ch", seq_len(n_channels)),
      type = rep("EEG", n_channels)
    ),
    samplingRate = sr
  )
}
