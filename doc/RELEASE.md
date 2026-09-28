# Releasing compress_video

This is the procedure for publishing a version to pub.dev. It is written for version 1.0.0.
Only Dan runs the steps under "Publish". No agent runs them.

**Publishing cannot be undone.** A published version can be retracted within 7 days, which
hides it from new installs. It can never be deleted, and the version number can never be used
again.

## Pre-publish checklist

Do these in order. Tick each box when it is done.

- [ ] 1. Re-run `doc/HARDWARE_CHECKLIST.md` against a **release** build, and record each result
      in that file with the date. This needs a physical Android phone (QUESTIONS.md #3), real
      phone clips (QUESTIONS.md #4) and the MacBook Air awake (QUESTIONS.md #8).
      - Phone: `cd example && flutter build apk --release`
      - MacBook Air: `cd example && flutter build ios --release --no-codesign`
      - MacBook Air: `cd example && flutter build macos --release`
- [ ] 2. Confirm that the latest CI run on `main` is green for `Android`, `Apple` and
      `Cross-platform parity`. In the `Android` job, check that `Dry-run publish` and
      `dartdoc: zero warnings (RELS-01)` passed, and the pana step if it is present (see
      "The pana score" below).
      - `gh run list --repo danieljamesjohnson/compress_video --branch main --limit 1`
- [ ] 3. Run `dart pub publish --dry-run` from the repository root. The last line must be
      `Package has 0 warnings.`
- [ ] 4. Decide the publisher (QUESTIONS.md #2). There are two options.
      - **Option A: publish under the Google account.** Publish as
        `danthebeliever@gmail.com`. The package page shows that address as the uploader. The
        package can be moved to a verified publisher later.
      - **Option B: publish under a verified publisher.** First create the publisher: on
        pub.dev, open the account menu, choose "Create publisher", and enter a domain you
        control, for example `danjjohnson.com`. pub.dev asks you to verify the domain in
        Google Search Console with a DNS TXT record. Then publish as in option A, open the
        package's "Admin" tab, and transfer the package to the publisher.
      - In both options the first publish is made from the Google account. Option B adds the
        transfer after it.

## Publish

Run these from the repository root, on a clean checkout of `main`.

1. Publish. The first time, the command opens a browser to sign in with Google.

   ```sh
   dart pub publish
   ```

2. Tag the release and push the tag to both remotes.

   ```sh
   git tag -a v1.0.0 -m "compress_video 1.0.0"
   git push github v1.0.0 && git push origin v1.0.0
   ```

3. Create the GitHub release. The notes are the 1.0.0 entry of CHANGELOG.md.

   ```sh
   gh release create v1.0.0 --repo danieljamesjohnson/compress_video --title "compress_video 1.0.0" --notes-file <(sed -n '/^## 1.0.0/,/^## 0.1.0/p' CHANGELOG.md | sed '$d')
   ```

## After publishing

- [ ] Open `https://pub.dev/packages/compress_video/score` and confirm 160/160. The score can
      take up to an hour to appear.
- [ ] If option B was chosen, transfer the package to the publisher from the "Admin" tab.
- [ ] Mark RELS-01 and ROADMAP criterion 1 complete in `.planning/`.
- [ ] Optional: post the link to `MIGRATION.md` on the `video_compress` issue tracker.

## The pana score

`pana` is the tool pub.dev uses to compute pub points. The plan for this release was to run it
in CI and fail unless the package is granted every point. That step is **not in CI yet**, and
pana has **not been run** against this package.

The reason: the release plan allowed pana to be installed only if pub.dev listed its publisher
as `dart.dev`. On 2026-09-27 pub.dev listed it as `tools.dart.dev`, so it was not installed.
QUESTIONS.md #2 has the details and the one decision needed.

Until that is settled, the gates that stand in for the score are `Dry-run publish` at 0
warnings, `dartdoc: zero warnings (RELS-01)`, and `flutter analyze --fatal-infos` with the
`public_member_api_docs` lint. They do not prove 160/160. The first item under "After
publishing" is the real check.

## For the next version

1. Set `version:` in `pubspec.yaml` and `s.version` in `darwin/compress_video.podspec` to the
   new number.
2. Add a `## <version>` entry at the top of CHANGELOG.md.
3. Follow this file from the top, with the new number in place of `1.0.0` and the new CHANGELOG
   heading in the `sed` command.
