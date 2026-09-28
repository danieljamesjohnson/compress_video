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
      `dartdoc: zero warnings (RELS-01)` and `pana: 160/160 pub points (RELS-01)` passed.
      - `gh run list --repo danieljamesjohnson/compress_video --branch main --limit 1`
- [ ] 3. Run `dart pub publish --dry-run` from the repository root. The last line must be
      `Package has 0 warnings.`
- [ ] 4. Decide the publisher (QUESTIONS.md #2). There are two options.
      - **Option A: publish under the Google account.** Publish as your Google account.
        The package page shows that account's address as the uploader. The package can be
        moved to a verified publisher later.
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

`pana` is the tool pub.dev uses to compute pub points. CI runs it in the `Android` job, in the
step `pana: 160/160 pub points (RELS-01)`, and fails unless the package is granted every point.
On 2026-09-27 the package scored 160 of 160 locally with pana 0.23.19.

pana's score before publishing and pub.dev's score after publishing come from the same tool,
but pub.dev runs its own copy. The first item under "After publishing" is the real check.

To run pana by hand, from the repository root:

```sh
dart pub global activate pana 0.23.19   # the version CI pins; bump both together
dart pub global run pana --flutter-sdk "$(dirname "$(dirname "$(command -v flutter)")")" .
```

## For the next version

1. Set `version:` in `pubspec.yaml` and `s.version` in `darwin/compress_video.podspec` to the
   new number.
2. Add a `## <version>` entry at the top of CHANGELOG.md.
3. Follow this file from the top, with the new number in place of `1.0.0` and the new CHANGELOG
   heading in the `sed` command.
