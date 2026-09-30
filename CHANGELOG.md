# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). While the major
version is 0, the plugin is still allowed to change its defaults.

## [Unreleased]

## [0.1.1] - 2026-09-30

Documentation and test coverage only: no change to what the plugin runs.

### Added

- test case `noncolocated`: a jj repository without `.git`, which a git-only
  implementation cannot answer at all
- test case `gitfirst`: a colocated repository whose rename jj has not
  snapshotted yet, pinning the fact that the backend order decides the answer
- `scripts/capture.sh` and `scripts/demo.lua`, which produce the demo image in
  the readme from a real terminal capture

### Changed

- readme: the demo image replaced the hand written listing, and the test
  section now lists what each case protects

## [0.1.0] - 2026-09-30

### Added

- a `voil` column for oil.nvim, registered through oil's own column registry
- jj and git backends, detected per directory and tried in a configurable order
- one async command per directory, cached, with a warning and a backoff when the
  command fails
- highlights derived from the colorscheme and re-derived on `ColorScheme`
- headless test suite with git and jj fixtures, running in CI

[Unreleased]: https://github.com/mercenarioZ/voil.nvim/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/mercenarioZ/voil.nvim/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/mercenarioZ/voil.nvim/releases/tag/v0.1.0
