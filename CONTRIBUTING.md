# Contributing

## Branches

`rewrite` is the default branch and the only active one — all pull
requests target `rewrite`. `master` holds the legacy Objective-C app
and is not developed anymore.

## Building

Only the Xcode Command Line Tools are needed (macOS 13 or later).

```sh
./build.sh            # builds build/HandBrake Batch.app (ad-hoc signed)
./build.sh --install  # also copies it to /Applications
./build.sh --dmg      # also makes build/HandBrake-Batch-<version>-universal.dmg
```

There is no Xcode project; the app is a SwiftPM executable
(`Package.swift`, sources in `Sources/HandBrakeBatch/`). For a quick
compile check without building the app bundle:

```sh
swift build
```

CI runs `swift build` on pushes and pull requests to `rewrite`.

## Making changes

- Keep user-facing behavior the same unless the change is the point of
  the PR; say what changed in the PR description.
- Add an entry to `CHANGELOG.md` under the next release heading for
  user-facing changes.
- Don't commit binaries, DMGs, or build output. The 45 MB of history
  is mostly HandBrakeCLI binaries committed by the original project
  years ago — `build.sh` already downloads the encoder at build time
  and caches it in `.cache/` (ignored by git), so there is no reason
  to add more.
- The app invokes HandBrakeCLI with an argument array, never a shell
  string. Keep it that way, and keep secrets out of command previews.

## Tests

```sh
swift test   # also runs in CI on pushes and pull requests to `rewrite`
```

The app's code lives in the `HandBrakeBatchCore` library target
(`Sources/HandBrakeBatchCore/`) so the `HandBrakeBatchTests` target
can `@testable import` it; the executable target is just `main.swift`,
the entry point. Keep that split: new app code goes in the library,
not in the executable. Current tests cover the pure logic —
`ProgressParser`, `Savings`, `QueueManager.arguments(for:scan:)`,
preset-file parsing, `Hardware.intelVTBitrate`, and the
`AppModel` path/language helpers. For behavior that needs a real
encode, verify with `swift build` and a real encode run.

## Commits

Sign your commits when you can (`git commit -S` with a configured
signing key), so the history stays verifiable.
