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

Exports run a bundled FFmpeg as a separate program, `Contents/Resources/ffmpeg`. KapKap builds it
from the unmodified sources below with `script/build_ffmpeg.sh`, which records every configure
option; the codecs are linked into that one executable.

| Component | Version | Source archive | License |
| --- | --- | --- | --- |
| FFmpeg | 8.1.2 | ffmpeg-8.1.2.tar.xz | GPL-3.0-or-later (built with --enable-gpl --enable-version3) |
| x264 | r3222 (b35605a) | x264-b35605a.tar.bz2 | GPL-2.0-or-later |
| x265 | 4.3 | x265_4.3.tar.gz | GPL-2.0-or-later |
| libvpx | 1.17.0 | libvpx-1.17.0.tar.gz | BSD-3-Clause |
| SVT-AV1 | 4.2.0 | SVT-AV1-v4.2.0.tar.bz2 | BSD-3-Clause-Clear, with the Alliance for Open Media patent license |
| Opus | 1.6.1 | opus-1.6.1.tar.gz | BSD-3-Clause |
| dav1d | 1.5.4 | dav1d-1.5.4.tar.bz2 | BSD-2-Clause |

The GNU license texts are in `Contents/Resources/Licenses`, and each component's own license and
patent files are in `Contents/Resources/Licenses/FFmpeg`. The complete source code of these
components, in exactly these versions, is attached to every GitHub release as
`KapKap-<version>-third-party-sources.tar` (https://github.com/design-ninja/KapKap/releases),
and `script/build_ffmpeg.sh` in KapKap's repository rebuilds the executable from it. You may
replace the bundled FFmpeg with your own build.
