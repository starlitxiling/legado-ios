# Archive dependencies

- Unrar.swift 0.5.4, revision `7216007a38ac122dbdeae26cfdaf7f10775c868f`: Swift wrapper under MIT, embedded Cunrar under the separate UnRAR license. Both licenses are included. No RAR encoder is implemented.
- PLzmaSDK 1.6.1, revision `1b27a1c9df85805342d1b049427d6d1dc7ce713d`: MIT wrapper and LZMA SDK 26.01 public-domain code. The upstream license is included.
- Upstream: https://github.com/mtgto/Unrar.swift and https://github.com/OlehKulykov/PLzmaSDK

Only decoding is used by the app. SWCompression remains in the independent historical probe; it is not linked into LegadoCore or the application.
