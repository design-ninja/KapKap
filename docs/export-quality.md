# Export quality

MP4 defaults to H.264 (`libx264`, CRF 16, `fast`), at the selected resolution and frame rate. High quality uses CRF 14 / `medium`. Keep original file is an explicit option available only for a full-length, unchanged MP4; it copies the bytes without compression. Both Save and Copy use the same export path. Recording masters stay unchanged.

The default was chosen from local measurements on 2026-09-17, on this Apple Silicon Mac running macOS 27. A 21.87-second UI recording with text and pointer movement was encoded at 30 fps at its original 3022×1622 resolution. The source was 1,705,728 bytes. Each encode was timed once, so small timing differences are not significant.

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
