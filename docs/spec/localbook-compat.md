# Local book compatibility

Reference: Android commit `2bdd3c58b`. P7 is being implemented incrementally.

## UMD

`UmdFile` reads text UMD headers, UTF-16LE title/author/kind, chapter offsets and titles, cover bytes and independently compressed zlib blocks. Chapter URLs are decimal indices, matching `UmdFile.kt`. Paragraph separator U+2029 becomes a newline. A 64 MiB combined body/cover limit and 100,000 chapter limit bound accepted content. Invalid lengths, truncated sections, damaged zlib checksums and invalid offsets throw contextual errors. Image-book UMD is rejected explicitly, as the reference reader does not implement its image blocks.

The parser cache uses file identity/size/modification time, at most three entries and 32 MiB total. Larger accepted books are parsed without caching. Files and remote-book import accept UMD and the existing MOBI reader also handles the AZW extension. Archive import is a subsequent P7 step.

The synthetic fixture was read with the original `modules/book` Java classes compiled from the pinned commit; only an Android annotation stub was supplied. The Swift tests assert the same output:

| Field | Android Java | Swift |
| --- | --- | --- |
| Title / author / kind | Synthetic UMD / Fixture Author / Fiction | Same |
| Chapter URLs / titles | 0 / Opening; 1 / Ending | Same |
| First body | First paragraph + newline + Second paragraph | Same |
| Last body | The final page. | Same |

Raw oracle output: `.build/round5/umd-oracle/output.log`. Every prefix shorter than the valid fixture is rejected by Swift. Cache tests cover reuse, modification invalidation and size exclusion.

From the iOS worktree root, no environment variables required:

```sh
rtk proxy python3 tools/localbook-fixtures/generate.py
rtk proxy swift test --package-path Packages/LegadoCore --filter UmdFileTests
```

The generator derives paths from its location and produces synthetic content only.

## ZIP, RAR and 7z

`BookArchive` provides ordered metadata, per-member bytes and extraction of all supported book files. ZIP uses the existing CRC-checked reader; RAR uses Unrar.swift 0.5.4; 7z uses the pinned PLzmaSDK revision in ArchiveLicenses/PROVENANCE.md. The initial SWCompression probe was superseded after source review found fatal short-read preconditions and unbounded eager header/content expansion. The replacement passed the required standalone macOS tests and iOS compilation before integration.

Members are validated for absolute/traversal paths and normalized collisions, ZIP symlinks are rejected, and native formats are decoded into data streams instead of allowing native extraction to create filesystem links. Default limits are 256 MiB compressed/expanded and 10,000 entries. Native codec internal header/dictionary allocations are controlled by the codec and are not a hard process-memory ceiling. RAR multivolume archives require a complete single archive; password parameters are available in the core API.

Local import hashes the original archive URL plus member path, preserving identity/progress on repeat import. Conflicts retain the original archive and only the conflicting members are retried when keeping copies. Remote members retain serverID and an archiveEntry attribute in their origin; missing-file restore fetches and reads that member. Network replay tests assert GET-only behavior.

## Import entry points

The app registers local book/archive document types and enables document opening in place and file sharing. File URLs received by the application open the import page. Folder scans persist security-scoped bookmarks, skip hidden items and symbolic links, and reject scans exceeding 10,000 entries. Import retains directory access for the duration of the operation. Online import accepts HTTP(S), bounds responses to 256 MiB, and uses UTF-8 Content-Disposition filename* / filename or the final URL name. Download originals remain in the managed hidden `.downloads` folder for conflict retries.

Directory and online import behavior is covered by `LocalImportEntryTests`; system document registration/open URL routing is build-verified and still awaits the combined simulator interaction pass.

## Text encoding detection

Sampling is 512,000 bytes. BOM and explicit HTML meta charset take precedence, followed by Unicode detection, Japanese kana statistics, Foundation's statistical detector constrained to the supported Japanese/Korean/Cyrillic/Western/Chinese encodings, and the existing GB/Big5 frequency fallback. This uses system Foundation/CoreFoundation and adds no dependency. It does not claim byte-for-byte equivalence with all 26 Android ICU recognizers; short ambiguous byte sequences remain inherently ambiguous.

Eight generated language fixtures decode through the final chapter without data loss, including Shift_JIS, EUC-JP, EUC-KR, Windows-1251/1252, ISO-8859-1, GBK and UTF-16. A Shift_JIS sample preceded by 70,000 ASCII spaces verifies the increased sampling window. HTML charset detection now accepts omitted/attributed head tags. The generator intentionally includes language text because encoding behavior is under test.


## TXT chapter rules and persistence

Specification: Kotlin `2bdd3c58b`, TextFile.kt:91-114,214-219,497-590. Scoring samples 512,000 bytes, counts headings separated by more than 1,000 UTF-16 units, penalizes gaps under 100, and replaces the selected rule only when its score exceeds the previous score by more than two. Short one/two-heading snippets can intentionally have no selected rule.

| Synthetic input | Kotlin rule | Swift result |
| --- | --- | --- |
| Five CH headings separated by 1,250 characters, with four false VOLUME headings per chapter | Narrow CH rule | Narrow CH rule |
| Single CH heading with short body | None | None |
| Manual CH rule with a 132,000-byte first chapter | Volume plus numbered children | Volume plus numbered children |
| Filename long.txt, index 0, title CH 1 | Middle 16 hex characters of MD5 | Fixed digest asserted |

Title replacement exposes book/result/index/prevTitle/prevLength/lastVolumeTitle and java.putVolume; front matter also runs through replacement. Rules and charset persist in book.tocUrl/charset. Modification time invalidates selection/encoding and reader directories; stored chapter revisions prevent stale body cache reuse. The parser streams decoding and offsets rather than loading whole TXT files. Existing byte-offset tests select a rule explicitly so they remain independent of auto-selection scoring.

Validation: `.build/round5/p7-toc-core.log` (682/0), `p7-toc-app.log` (277/0), `p7-modified-red.log` (3/0, the existing chapter reload already retained stored cache revisions). iPhone testing is deferred at the user's request.
