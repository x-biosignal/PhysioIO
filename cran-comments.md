## Test environments

* Local: Ubuntu 24.04, R 4.5.2
* win-builder (planned): R-devel and R-release
* macbuilder (planned): R-release
* R-hub v2 (planned): linux, windows, macos

## R CMD check results

Local `R CMD check --as-cran` gives:

    0 errors | 2 warnings | 0 notes

Both warnings are environmental (explained below) and collapse on CRAN's own
infrastructure to the single expected

    0 errors | 0 warnings | 1 note      (New submission)

## Notes

* This is a new submission, so the CRAN incoming feasibility check reports
  (as a WARNING locally, because a strong dependency is not yet on a mainstream
  repository; this becomes the standard "New submission" NOTE on CRAN once
  PhysioCore is accepted):

      Maintainer: 'Yusuke Matsui <mail.to.matsui@gmail.com>'
      New submission

  This is expected for a first-time submission.

* The incoming feasibility check also reports:

      Strong dependencies not in mainstream repositories:
        PhysioCore

  PhysioCore is a sibling package from the same physiological-signal ecosystem
  and is being submitted to CRAN immediately before this package (see the
  reverse-dependency note below).

* The URL checker reports some URLs as "possibly invalid":

  * The `https://github.com/x-biosignal/...` links (from README.md) and
    `https://x-biosignal.github.io/PhysioIO/` (from DESCRIPTION) point to the
    public project repository and pkgdown site. They resolve once the public
    mirror is published together with this submission.
  * `https://www.mathworks.com/help/matlab/import_export/mat-file-versions.html`
    returns HTTP 403 (Forbidden) to automated requests but is reachable in a
    browser; it is a stable, correct documentation reference.

* The optional `qpdf` system tool is absent from the local check host, so the
  check reports a WARNING that it "is needed for checks on size reduction of
  PDFs". The package ships no PDFs (its vignettes build to HTML) and `qpdf` is
  present on CRAN / win-builder / macbuilder / R-hub, where this does not appear.

* On some check systems the following may additionally appear and are
  environmental rather than package problems:

  * "unable to verify current time" -- a transient failure to contact an
    external time server on the build host.
  * "possibly misspelled words in DESCRIPTION" -- the flagged tokens are
    signal-format and standard names given in single quotes (e.g. 'EDF',
    'EDF+', 'BDF', 'GDF', 'BrainVision', 'HDF5', 'BIDS', 'MATLAB', 'DuckDB')
    and the class name 'SummarizedExperiment'; these are spelled correctly.
  * "'qpdf' is needed for checks on size reduction of PDFs" -- appears only
    when the optional 'qpdf' system tool is absent from the check host.

## Reverse dependencies

This package is one of a family of intra-ecosystem sibling packages. To keep
inter-package dependencies resolvable, the packages are submitted in
dependency order:

    PhysioCore -> PhysioIO / PhysioPreprocess -> PhysioAnalysis

PhysioIO depends on PhysioCore (submitted immediately before this package) and
is only a Suggests-level dependency for downstream siblings. No other reverse
dependencies exist on CRAN at submission time.
