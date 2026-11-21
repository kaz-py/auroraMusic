# Experimental progressive playback

Windows and Android support `SourceBackend.supportsExperimentalProgressivePlayback`
and `setExperimentalProgressivePlayback(bool)`. The default is false. Each resolve
captures the setting, so switching it changes the next playback. With the setting
off, the existing fully downloaded and validated cache path remains in use.

The experiment selects direct HTTPS WebM audio through the bundled yt-dlp
downloader. Other containers, fragmented protocols, and unknown durations use the
stable complete-download path. FFmpeg reads a tokenized IPv4 loopback HTTP relay,
never the growing file directly. Initial GET can stream with unknown length;
unknown-length open-ended nonzero and suffix ranges wait for validated completion.
Known-length ranges wait for missing bytes. No failure returns a successful EOF.
`ResolvedAudio.validateCompletion` also gates the PCM pump's clean EOF, so an
FFmpeg decoder that exits successfully after an HTTP abort cannot advance the
queue before progressive validation succeeds.

Private staged audio is promoted atomically only after size, audio track, duration
agreement, and complete local FFmpeg decode checks. Cached plus staged bytes are
bounded by a 512 MiB reservation, and unknown-size downloads reserve the full cap.
The relay checks growth every 50 ms, cancels after 90 seconds without progress,
limits active HTTP clients to eight, and closes on resolve cancellation, next
playback, or source disposal. Download continues while the player is paused.
Clearing the cache refuses to race a download and maps a loaded relay URL to its
published file so it stays protected after completion.

Run focused deterministic checks:

```powershell
C:/flutter/flutter/bin/flutter.bat test --no-pub test/progressive_audio_relay_test.dart test/progressive_source_test.dart test/source_backend_test.dart test/audio_completion_test.dart
C:/flutter/flutter/bin/dart.bat analyze lib/sources/progressive_audio_relay.dart lib/sources/yt_dlp_source.dart test/progressive_audio_relay_test.dart test/progressive_source_test.dart
```

The offline smoke generates a genuine 12-second Opus WebM, writes 4 KiB every
90 ms, requires PCM before completion, and checks forward and backward seek frame
counts without false EOF. Opus seeks permit 1 ms of encoder delay. It requires no
network, personal music, Flutter native build, or additional dependency.

Device checks still required on Windows and Android:

1. Leave the option off and verify a fresh song waits for complete download. Turn
   it on and throttle the connection: a fresh WebM song should begin before the
   download completes. A cache hit should remain immediate.
2. Seek backward, then beyond the downloaded range. Verify buffering resolves,
   playback remains at the requested position, and the queue does not advance.
   Pause during buffering and verify recovery preserves the paused intent.
3. Disable the option during playback: the current relay should continue, with
   the next new song using full download. Stop, switch tracks, and close the app
   during a download; verify the private staging input is removed after cancellation.
4. Interrupt the network or reject the download, verify no trusted cache entry is
   created, and retry. Clear the cache during playback and verify the loaded
   input remains usable. Try an unsupported container and verify full-download
   fallback.
5. On Android, include an API 24/25 device and background playback. Loopback trust
   is limited to `http://127.0.0.1:<port>/aurora-progressive/<64 hex characters>`;
   remote HTTPS still verifies TLS. No general HTTP or arbitrary file route is added.

The worker's Windows offline FFmpeg proof passed with 576000 complete frames,
144048 frames after seeking to 9 seconds, and 528048 after seeking to 1 second.
Android hardware, Bluetooth, background lifecycle, and upstream YouTube access
must be checked separately; fake native channel tests do not establish those.
