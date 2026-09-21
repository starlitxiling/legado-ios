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
