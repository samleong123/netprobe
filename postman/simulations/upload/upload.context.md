# Upload simulation

## Purpose

Exercise the native upload engine over HTTP with the contract fixtures in
`postman/mocks/upload/default.js`, including custom responses without a size.

## Execution

Start `postman simulation run postman/simulations/upload/upload.sim.yaml --port auto --output ndjson --no-history`.
Use the upload member URL from its `listening` event as the argument to
`bash scripts/check-native.sh <upload-member-url>`. Stop the simulation with Ctrl-C.

## Assumptions

- The fixtures model the existing received-size parser and the requested custom
  HTTP success behavior. They were derived from this app and the task; no live
  provider or device network is exercised. (reasoned 2026-10-26)

## Observations

<!-- begin:observations -->
2026-10-26: The upload member served no traffic because the sandbox denied
binding the simulation's local port. The separate native checks passed.
<!-- end:observations -->

## What didn't work

- 2026-10-26: Startup failed with `listen EPERM: operation not permitted 127.0.0.1`.
  Local HTTP verification remains pending in an environment that allows listening.
