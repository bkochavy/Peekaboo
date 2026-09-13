# Ben's Peekaboo builds

Fork: https://github.com/bkochavy/Peekaboo
Upstream: https://github.com/Emanuele-web04/Peekaboo

`PersonalBuild.json` records the shared Mac/iPhone identity. The build wrapper
checks out a recorded commit into `PersonalBuilds/`, substitutes the team,
bundle ID and corresponding iCloud container together, then runs the maintained
upstream project generator and verification. The upstream source stays intact.

The identity change is necessary because Ben's developer team does not own the
author's app or CloudKit container. All other upstream sync requirements apply,
including Production CloudKit and APNs for Release, separate development stores,
explicit CloudKit linking, and real-device two-way sync verification. This
identity configuration has not yet passed production device sync verification.

## Build

Install current Ruby and run `bundle install` using the committed Gemfile.lock.
On this server, prepend `/opt/homebrew/opt/ruby/bin` to PATH.
Commit source changes first: builds use HEAD, never uncommitted source changes.

```sh
python3 Scripts/personal-build.py mac --build 1
python3 Scripts/personal-build.py ios --build 1
```

Those commands verify compilation without signing. Outputs include commit,
platform, build number and identity in `provenance.json`. Each output directory
is exclusive; choose a fresh build number for another run.

For signed archives set `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_PATH`,
and optionally `PEEKABOO_SIGNING_KEYCHAIN` to an existing unlocked CI keychain.
Set `ASC_BYPASS_KEYCHAIN=1` for `asc` commands to use API credentials from the
environment. Never commit API keys, certificates, passwords or private keys.

```sh
python3 Scripts/personal-build.py mac --build 2 --archive --export --profile 'Peekaboo Mac App Store'
python3 Scripts/personal-build.py ios --build 2 --archive --export --profile 'Peekaboo iOS App Store'
```

These commands require the app's iCloud container and provisioning profiles to
exist. Before TestFlight, create the App Store Connect record for both platforms,
deploy the CloudKit schema to Production, inspect archive entitlements and
CloudKit linkage, and upload each platform's exported artifact with `asc`.
Assign both processed builds to Ben's TestFlight group. Install from TestFlight
on the destination devices and complete the two-way sync checks in AGENTS.md.
An unsigned build or development install is not a TestFlight substitute.

## Bring in updates

In this checkout `origin` is upstream and `personal` is Ben's fork:

```sh
git fetch origin
git merge origin/main
git push personal HEAD:main
```

Review upstream changes, especially signing, models and entitlements. Then run
both build commands with new build numbers. On another clone, check `git remote
-v` and add upstream if needed; do not assume the same remote names.

Automatic uploads and Mac installation are not enabled yet. They require the
initial Apple setup, production sync acceptance and the reachable destination.

## Setup status (September 12, 2026)

- Both upstream and personal-identity Mac/iPhone builds compile with Xcode 26.3.
- Project generation is deterministic, CloudKit linkage is checked, and the
  forbidden temporary Mach lookup entitlement is absent.
- Apple registered the universal bundle ID `com.kochavy.peekaboo` as
  `J8T2TZBCCD`, with CloudKit and push notification capabilities enabled.
- The server has working API-file authentication and an existing CI distribution
  identity. Source the ignored `.env.personal` for the server's credential paths.
  Credentials themselves remain outside this repository.
- Still required: create and associate `iCloud.com.kochavy.peekaboo`, initialize
  and deploy its Production schema, create the iOS/macOS App Store Connect app
  record and platform provisioning profiles, archive/export/upload, assign the
  processed builds to TestFlight, install, and verify real-device two-way sync.
- No signed distribution, TestFlight invitation, remote installation, or live
  synchronization has been completed or verified.
