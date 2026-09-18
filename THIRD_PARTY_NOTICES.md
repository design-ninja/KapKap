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

## Export tools

Local builds bundle the installed ARM FFmpeg and its linked libraries from Homebrew.
FFmpeg: https://ffmpeg.org/legal.html
Homebrew formula and build configuration: https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/f/ffmpeg.rb

The installed encoder build includes GPL components (including x264/x265). This local
development bundle is not a public release. Before distributing it, collect the exact
library licenses, corresponding source/build instructions and notices for the bundled
versions, and choose a compatible distribution license for KapKap. Developer ID signing
and notarization also remain release work.
