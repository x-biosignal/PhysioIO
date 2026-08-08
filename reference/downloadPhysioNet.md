# Download a WFDB record from PhysioNet

Downloads the `.hea`, `.dat` and (optionally) annotation files of a
record from a PhysioNet database into `dest`.

## Usage

``` r
downloadPhysioNet(
  record,
  database,
  dest = ".",
  annotator = "atr",
  base_url = "https://physionet.org/files"
)
```

## Arguments

- record:

  Record name (e.g. `"100"`).

- database:

  PhysioNet database slug (e.g. `"mitdb"`).

- dest:

  Destination directory (created if needed).

- annotator:

  Optional annotation extension(s) to fetch (e.g. `"atr"`).

- base_url:

  PhysioNet base URL.

## Value

The paths of the downloaded files, invisibly.
