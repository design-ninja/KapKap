# Export quality

Video exports offer three qualities, chosen in the editor bar and remembered between exports. Each
maps to a constant rate factor per encoder; lower keeps more detail and makes a bigger file.

| Quality | MP4 (H.264, `fast`) | HEVC (`medium`) | WebM (VP9) and AV1 |
| --- | ---: | ---: | ---: |
| Smaller file | CRF 28 | CRF 30 | CRF 42 |
| Balanced (default) | CRF 20 | CRF 22 | CRF 32 |
| Best quality | CRF 14 | CRF 16 | CRF 22 |

## Fast Hardware Encoding

MP4 and HEVC can be encoded on the Mac's media engine (VideoToolbox) instead of x264 or x265. It is
off by default and chosen from the quality menu. VideoToolbox's constant quality runs from 1 to 100;
the three qualities use 40, 60 and 75, which gave the busy clip below about the SSIM of x264 at the
matching CRF (VideoToolbox 35 and 45 bracketed CRF 28; 75 matched CRF 14).

Measured on 2026-09-30 on an Apple Silicon Mac running macOS 27, Balanced, each encode timed once:

| 8 s, 1920×1080, 60 fps, moving fractal with film grain | Seconds | Bytes | SSIM |
| --- | ---: | ---: | ---: |
| H.264 x264 CRF 20, fast | 3.84 | 25,528,534 | 0.9914 |
| H.264 VideoToolbox 60 | 1.87 | 32,357,206 | 0.9907 |
| HEVC x265 CRF 22, medium | 8.47 | 18,853,872 | 0.9881 |
| HEVC VideoToolbox 60 | 1.99 | 31,124,495 | 0.9899 |

| 5 s, 3024×1964, 30 fps, KapKap interface recording | Seconds | Bytes | SSIM |
| --- | ---: | ---: | ---: |
| H.264 x264 CRF 20, fast | 1.10 | 1,001,184 | 0.9989 |
| H.264 VideoToolbox 60 | 1.68 | 3,195,151 | 0.9970 |
| HEVC x265 CRF 22, medium | 3.08 | 1,114,280 | 0.9987 |
| HEVC VideoToolbox 60 | 1.80 | 2,733,297 | 0.9973 |

On busy footage the media engine is about twice as fast as x264 and four times as fast as x265, for
files 1.3 to 1.7 times bigger at about the same SSIM. On a still interface x264 is already faster, and the
hardware file is three times bigger and slightly softer, so software stays the default. x265's fast
preset was also tried: 7.62 s on the busy clip and a bigger, softer file on the interface, so HEVC
keeps medium.

## Qualities and history

GIF and APNG have no quality choice. Every export is re-encoded; the former "Keep original file"
option, which copied an unchanged MP4 byte for byte, was removed. Save, Copy and Open With share
the same export path, and recording masters stay unchanged. On a 2.4-second full-screen recording
at 3024×1964, the three MP4 qualities produced 262 KB, 580 KB and 1.17 MB.

The measurements below date from before the three qualities, when MP4 had a single CRF 16
default with an optional CRF 14.

That default was chosen from local measurements on 2026-09-17, on this Apple Silicon Mac running macOS 27. A 21.87-second UI recording with text and pointer movement was encoded at 30 fps at its original 3022×1622 resolution. The source was 1,705,728 bytes. Each encode was timed once, so small timing differences are not significant.

| Encoder | Output bytes | Encoding seconds | SSIM against source |
| --- | ---: | ---: | ---: |
| H.264 CRF 16, medium | 1,077,061 | 2.72 | 0.999799 |
| H.264 CRF 18, fast (previous default) | 862,491 | 2.81 | 0.999690 |
| H.264 CRF 18, medium | 926,144 | 2.56 | 0.999708 |
| H.264 CRF 20, fast | 737,476 | 2.71 | 0.999542 |
| AV1 CRF 26, preset 8, 4 logical processors | 1,274,455 | 3.84 | 0.999804 |

A separate six-second slice tested hardware HEVC using VideoToolbox: quality 65 produced 833,383 bytes in 1.76 s; quality 75 produced 1,102,342 bytes in 1.73 s. H.264 CRF 20 / fast on the same slice produced 182,218 bytes in 0.83 s. These settings did not justify making HEVC the default for this screen-content workload. Other content and encoder settings can behave differently.

SSIM was calculated after aligning timestamps, normalizing to 30 fps and yuv420p. It is a diagnostic, not a guarantee of perceptual equivalence. A text-heavy crop at eight seconds was also inspected side by side at native pixel size. The balanced result had no obvious loss of text readability in that crop. This is lossy encoding; no claim of mathematically lossless compression is made. Telegram may separately transcode an uploaded video.

Selected recording FPS are embedded in new recording metadata rather than inferred from a variable-frame-rate track's nominal frame rate. Old recordings without this metadata retain the inference fallback; the user can choose the desired FPS in export settings.

## Follow-up: user-provided recordings at 11:09 and 11:18

The first file is a 3024×1964 full-screen recording (2,839,996 bytes, 8.92 s); the second is a 3022×1618 area export (634,754 bytes, 8.53 s). They contain different UI states and capture bounds, so comparing their file sizes or SSIM directly would be misleading. Native-size text crops from the second export and its matching master showed softness already in the master.

The same 11:18 master (1,142,820 bytes) was encoded at original resolution and 30 fps:

| H.264 fast profile | Output bytes | Encoding seconds (single run) | SSIM against master |
| --- | ---: | ---: | ---: |
| CRF 18, previous default | 634,754 | 1.51 | 0.999529 |
| CRF 16, new default | 744,039 | 1.41 | 0.999662 |
| CRF 14 | 885,452 | 1.57 | 0.999770 |

The default trades a 17.2% size increase on this clip for less additional compression damage. The small time differences are noise, not evidence of faster encoding. These measurements cannot establish capture fidelity because their reference is already compressed.

Capture now requests ScreenCaptureKit's best resolution and uses the content filter's pixel scale. Crop origins and extents are snapped inward to an even physical-pixel grid before setting both sourceRect and output dimensions. Previously only output dimensions were rounded, allowing a fractional crop to be resampled into a slightly smaller frame. This fixes a potential source of text softness; it cannot restore details in existing recordings. At most fewer than four pixels per dimension are cropped by alignment. Geometry tests cover fractional Retina/non-Retina selections and unchanged full-display bounds.
