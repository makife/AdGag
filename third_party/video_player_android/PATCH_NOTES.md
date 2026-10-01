# video_player_android 2.12.2 — AdGag patch

Vendored from pub.dev (BSD-3, LICENSE kept; `example/` and `test/` omitted,
dev_dependencies removed) and used via `dependency_overrides` in the root
pubspec.yaml.

## The one change (marked `ADGAG PATCH`)

`TextureVideoPlayer.create` and `PlatformViewVideoPlayer.create` always give
ExoPlayer a `DefaultLoadControl` with

| | ExoPlayer default | AdGag |
|---|---|---|
| minBufferMs | 50000 | 15000 |
| maxBufferMs | 50000 | 30000 |
| bufferForPlaybackMs | 2500 | 700 |
| bufferForPlaybackAfterRebufferMs | 5000 | 2000 |

Why: Ads are 2-30s HLS streams from Mux with 5s segments. ExoPlayer waits
for 2.5s of buffered media before starting, so a feed video sat on its
thumbnail for seconds (owner: "Instagram starts the moment I swipe").
The backBufferDurationMs option still works as before.

## Removing it

Delete this folder and the `video_player_android` entry under
`dependency_overrides` in pubspec.yaml. Re-vendor (copy the new version from
the pub cache, reapply the block) when bumping video_player.
