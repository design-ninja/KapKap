# Third-party components

KapKap's interface and workflow are based on Kap by Wulkano: https://github.com/wulkano/Kap.
The Swift implementation is new. No Electron or Node.js runtime or Kap plugin code is included.

## Kap — MIT License

Copyright (c) Wulkano hello@wulkano.com (https://wulkano.com)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Sparkle — MIT License

Updates are installed with Sparkle 2 (https://sparkle-project.org), MIT-licensed;
see https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE.

## Export tools

Exports run a bundled FFmpeg as a separate program. It and the libraries it loads are built by
Homebrew (https://github.com/Homebrew/homebrew-core) and are unmodified.

| Component | Version | License |
| --- | --- | --- |
| FFmpeg | 8.1.2 | GPL-3.0-or-later (built with --enable-gpl --enable-version3) |
| x264 | r3222 (b35605a) | GPL-2.0-or-later |
| x265 | 4.2 | GPL-2.0-or-later |
| LAME | 4.0 | LGPL-2.0-or-later |
| mpg123 | 1.33.7 | LGPL-2.1-only |
| SVT-AV1 | 4.2.0 | BSD-3-Clause |
| dav1d | 1.5.4 | BSD-2-Clause |
| libvpx | 1.16.0 | BSD-3-Clause |
| Opus | 1.6.1 | BSD-3-Clause |
| libvmaf | 3.2.0 | BSD-2-Clause-Patent |
| OpenSSL | 3.6.3 | Apache-2.0 |

The GNU license texts are in `Contents/Resources/Licenses` inside the app. The complete source
code of the GPL and LGPL components above, in exactly these versions, is attached to every
GitHub release as `KapKap-<version>-third-party-sources.tar`
(https://github.com/design-ninja/KapKap/releases). The build recipes are the Homebrew formulae
for these versions. You may replace the bundled FFmpeg with your own build: it is
`Contents/Resources/ffmpeg`, with its libraries in `Contents/Frameworks`.
