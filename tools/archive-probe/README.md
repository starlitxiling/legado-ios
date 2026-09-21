# Archive dependency probe

This standalone package verifies the second candidate from round 5 PLAN section 6:
Unrar.swift 0.5.4 plus SWCompression 4.8.7. It does not modify the app or LegadoCore.
The probe reads archive members into memory; it is not a production extraction API.

From the iOS worktree root, with Xcode selected and no environment variables required:

```sh
rtk proxy swift test --package-path tools/archive-probe --disable-sandbox
```

From `tools/archive-probe`, build the iOS 17 library and its dependencies:

```sh
rtk proxy xcodebuild -scheme ArchiveProbe -destination 'generic/platform=iOS' -configuration Debug -derivedDataPath ../../.build/round5/ArchiveProbeDerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

The three checked-in fixtures contain only synthetic ASCII text. Tests need no
external archiver. Optional regeneration, from the worktree root, requires `7z`
and `rar` on PATH (tested generators: p7zip 17.05 and RAR 7.22):

```sh
rtk proxy python3 tools/archive-probe/generate_fixtures.py
```

Regeneration embeds filesystem timestamps, so binary hashes may change while
decoded content remains identical. Fixtures cover unencrypted LZMA 7z, LZMA2
solid 7z with two members, and compressed RAR5. RAR4, encryption, split volumes,
large archives, malformed archives, and production extraction limits are untested.

PLzmaSDK was eliminated during capability inspection: its official README and
`swift/Types.swift` FileType list 7z, xz, and tar, without RAR support:
https://github.com/OlehKulykov/PLzmaSDK/tree/1b27a1c9df85805342d1b049427d6d1dc7ce713d

SWCompression and its linked BitByteData 2.0.4 dependency use MIT licenses.
Unrar.swift's Swift wrapper uses MIT; its bundled UnRAR C++ code has the separate
UnRAR license, including restrictions on creating RAR compression software.
Production integration must retain their license notices.

The detailed run report is `.build/round5/archive-probe.md` at the worktree root.

## Production selection update (2026-09-21)

The production implementation uses Unrar.swift for RAR and PLzmaSDK revision `1b27a1c9df85805342d1b049427d6d1dc7ce713d` for 7z. The original SWCompression probe remains reproducible. Review found that SWCompression's BitByteData readers use process-terminating preconditions on short reads and that header/content decoding is not bounded through its public API. The native 7z candidate supports entry-wise streams and rejects all truncated prefixes in the probe.

`NativeSevenZipTests` passed LZMA, solid LZMA2 and every truncated prefix; the package also passed a generic iOS build. Initial truncation assertions used XCTest's throwing autoclosure incorrectly; moving the throwing call outside the assertion fixed the test harness. No decoder failure was concealed.

Run from this directory with no required environment variables:

```sh
rtk proxy swift test --filter NativeSevenZipTests
rtk proxy xcodebuild -scheme ArchiveProbe -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
