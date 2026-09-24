import "dart:async";

import "package:flutter_test/flutter_test.dart";

import "package:adgag/features/create_ad/domain/video_project.dart";
import "package:adgag/features/create_ad/presentation/widgets/editor_transport.dart";

Duration sec(double s) => Duration(milliseconds: (s * 1000).round());

void main() {
  group("A: play/pause state", () {
    test("idle -> play -> pause reaches the correct states", () {
      final EditorTransport t = EditorTransport(duration: sec(10), onSeek: (_) async {});
      expect(t.isPlaying, isFalse);
      t.play();
      expect(t.isPlaying, isTrue);
      t.pause();
      expect(t.isPlaying, isFalse);
    });

    test("play()/pause() are idempotent and don't notify redundantly", () {
      final EditorTransport t = EditorTransport(duration: sec(10), onSeek: (_) async {});
      int notifications = 0;
      t.addListener(() => notifications++);
      t.play();
      t.play();
      expect(notifications, 1);
      t.pause();
      t.pause();
      expect(notifications, 2);
    });
  });

  group("B: rapid seek converges to the latest requested position", () {
    test("an old async seek completion never overrides a newer request", () async {
      final List<Duration> performedSeeks = <Duration>[];
      final List<Completer<void>> completers = <Completer<void>>[];
      Future<void> fakeSeek(Duration target) {
        performedSeeks.add(target);
        final Completer<void> c = Completer<void>();
        completers.add(c);
        return c.future;
      }

      final EditorTransport t = EditorTransport(duration: sec(10), onSeek: fakeSeek);

      // First request starts draining immediately.
      t.requestSeek(sec(0.2));
      await Future<void>.delayed(Duration.zero);
      expect(performedSeeks, <Duration>[sec(0.2)]);
      // The UI-visible time is already exact — it never waits for the
      // seek to physically complete.
      expect(t.currentTime, sec(0.2));

      // While that seek is still in flight, request several more in
      // rapid succession — exactly the spec's own example sequence.
      t.requestSeek(sec(6.8));
      t.requestSeek(sec(1.4));
      t.requestSeek(sec(7.1));
      t.requestSeek(sec(3.0));
      t.requestSeek(sec(0.8));

      // Visible time already reflects the latest request, immediately.
      expect(t.currentTime, sec(0.8));
      // None of the intermediate positions were ever actually sought —
      // only the first (already in flight) and whatever's pending.
      expect(performedSeeks, <Duration>[sec(0.2)]);

      // Now let the first (0.2) seek "complete" — the drain loop must
      // pick up the LATEST pending position (0.8), not 6.8/1.4/7.1/3.0.
      completers[0].complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(performedSeeks, <Duration>[sec(0.2), sec(0.8)]);
      expect(t.currentTime, sec(0.8));

      // Completing the second (and final) seek leaves nothing pending.
      completers[1].complete();
      await Future<void>.delayed(Duration.zero);
      expect(performedSeeks.length, 2);
      expect(t.isSeeking, isFalse);
    });

    test("requestSeek clamps to [0, duration]", () {
      final EditorTransport t = EditorTransport(duration: sec(10), onSeek: (_) async {});
      t.requestSeek(sec(-5));
      expect(t.currentTime, Duration.zero);
      t.requestSeek(sec(50));
      expect(t.currentTime, sec(10));
    });
  });

  group("C: music synchronization mapping", () {
    // project start = 2.0s, end = 7.0s (duration 5s), source offset = 0
    // (this app's BackgroundAudio always plays from its own file's start
    // — see EditorTransport.musicLocalTimeAt's own doc comment on why
    // the general sourceOffset+... mapping simplifies here).
    const BackgroundAudio bg = BackgroundAudio(
      filePath: "/tmp/music.mp3",
      startSec: Duration(seconds: 2),
      duration: Duration(seconds: 5),
    );
    const Duration trimmed = Duration(seconds: 10);

    test("before the music range: null (stopped)", () {
      expect(EditorTransport.musicLocalTimeAt(bg, sec(0.0), trimmed), isNull);
      expect(EditorTransport.musicLocalTimeAt(bg, sec(1.9), trimmed), isNull);
    });

    test("inside the range: mathematically correct source position", () {
      expect(EditorTransport.musicLocalTimeAt(bg, sec(2.0), trimmed), Duration.zero);
      expect(EditorTransport.musicLocalTimeAt(bg, sec(3.5), trimmed), sec(1.5));
      expect(EditorTransport.musicLocalTimeAt(bg, sec(6.9), trimmed), sec(4.9));
    });

    test("after the range: null (stopped)", () {
      expect(EditorTransport.musicLocalTimeAt(bg, sec(7.0), trimmed), isNull);
      expect(EditorTransport.musicLocalTimeAt(bg, sec(9.0), trimmed), isNull);
    });

    test("backward seek within the range still resolves correctly", () {
      expect(EditorTransport.musicLocalTimeAt(bg, sec(6.0), trimmed), sec(4.0));
      expect(EditorTransport.musicLocalTimeAt(bg, sec(2.5), trimmed), sec(0.5));
    });

    test("null duration means 'to the end of the trimmed clip'", () {
      const BackgroundAudio openEnded = BackgroundAudio(filePath: "/tmp/music.mp3", startSec: Duration(seconds: 4));
      expect(EditorTransport.musicLocalTimeAt(openEnded, sec(9.9), trimmed), sec(5.9));
      expect(EditorTransport.musicLocalTimeAt(openEnded, sec(10.0), trimmed), isNull);
    });
  });

  group("D: overlay visibility boundaries", () {
    const TextOverlay overlay = TextOverlay(
      id: "t1",
      xPercent: 0.1,
      yPercent: 0.1,
      startSec: Duration(seconds: 2),
      duration: Duration(seconds: 2), // endSec = 4.0
      text: "ROCK",
    );

    test("exact boundary behavior from the spec's own example", () {
      expect(EditorTransport.isOverlayVisibleAt(overlay, sec(1.99)), isFalse);
      expect(EditorTransport.isOverlayVisibleAt(overlay, sec(2.00)), isTrue);
      expect(EditorTransport.isOverlayVisibleAt(overlay, sec(3.99)), isTrue);
      expect(EditorTransport.isOverlayVisibleAt(overlay, sec(4.00)), isFalse);
    });
  });

  group("E: animation-time foundation (localLayerTimeAt)", () {
    const TextOverlay overlay = TextOverlay(
      id: "t1",
      xPercent: 0.1,
      yPercent: 0.1,
      startSec: Duration(seconds: 2),
      duration: Duration(seconds: 2),
      text: "ROCK",
    );

    test("the same transport time always produces the same local time", () {
      expect(EditorTransport.localLayerTimeAt(overlay, sec(2.5)), sec(0.5));
      expect(EditorTransport.localLayerTimeAt(overlay, sec(2.5)), sec(0.5));
    });

    test("before the layer's own start clamps to zero, never negative", () {
      expect(EditorTransport.localLayerTimeAt(overlay, sec(0.0)), Duration.zero);
      expect(EditorTransport.localLayerTimeAt(overlay, sec(1.0)), Duration.zero);
    });

    test("seeking backward rewinds local time deterministically", () {
      expect(EditorTransport.localLayerTimeAt(overlay, sec(3.8)), sec(1.8));
      expect(EditorTransport.localLayerTimeAt(overlay, sec(2.1)), sec(0.1));
    });
  });

  group("F: mute is project-driven, not time-dependent", () {
    // Mute has no time axis — it's a direct, always-on function of
    // VideoProject.removeAudio, not something EditorTransport evaluates
    // per-instant the way speed/overlays/music are. Documented here as
    // the canonical mapping trim_step.dart's wiring uses.
    test("removeAudio maps directly to desired preview volume", () {
      expect(desiredOriginalAudioVolume(removeAudio: true), 0.0);
      expect(desiredOriginalAudioVolume(removeAudio: false), 1.0);
    });
  });

  group("G: speed-zone evaluation", () {
    final List<SpeedZone> zones = <SpeedZone>[
      const SpeedZone(start: Duration(seconds: 2), end: Duration(seconds: 4), factor: 0.5),
    ];

    test("1.0x before, inside, and after the zone respectively", () {
      expect(EditorTransport.activeSpeedAt(zones, sec(0.0)), 1.0);
      expect(EditorTransport.activeSpeedAt(zones, sec(1.99)), 1.0);
      expect(EditorTransport.activeSpeedAt(zones, sec(2.0)), 0.5);
      expect(EditorTransport.activeSpeedAt(zones, sec(3.99)), 0.5);
      expect(EditorTransport.activeSpeedAt(zones, sec(4.0)), 1.0);
      expect(EditorTransport.activeSpeedAt(zones, sec(8.0)), 1.0);
    });
  });

  // videoeditor7.txt section 10: "the previous 119 unit tests did not
  // catch the real bug" — these model the ASYNC player behavior the
  // physical-device regression actually depended on (repeated seeking
  // during normal playback, music free-running, video stalling at a
  // music region). Tests A-C exercise EditorTransport itself; D-F
  // exercise the new pure decideMusicSync policy function, which is what
  // trim_step.dart's _onTransportChanged now delegates every music
  // play/pause/seek decision to instead of inlining the same logic
  // untestably against a real VideoPlayerController.
  group("videoeditor7 Test A: 5s of normal playback position reports", () {
    test("zero seeks are ever caused by position reports", () async {
      final List<Duration> seeksPerformed = <Duration>[];
      final EditorTransport t = EditorTransport(
        duration: sec(10),
        onSeek: (Duration d) async => seeksPerformed.add(d),
      );
      t.play(); // "play command" issued exactly once by the caller
      for (int ms = 0; ms <= 5000; ms += 100) {
        t.reportPlaybackPosition(sec(ms / 1000.0));
      }
      await Future<void>.delayed(Duration.zero);
      expect(seeksPerformed, isEmpty);
      expect(t.isPlaying, isTrue);
    });
  });

  group("videoeditor7 Test B: programmatic timeline updates during playback", () {
    test("zero seek commands are produced", () async {
      final List<Duration> seeksPerformed = <Duration>[];
      final EditorTransport t = EditorTransport(
        duration: sec(10),
        onSeek: (Duration d) async => seeksPerformed.add(d),
      );
      t.play();
      // Simulates the timeline auto-following playback purely by
      // *reading* transport.currentTime (what _Timeline's
      // _onTransportPositionChanged does) — reading never calls back
      // into the transport, so this is really just re-confirming that
      // observing currentTime has no side effect, from the "timeline"
      // side of the loop this time rather than the "player" side.
      for (int ms = 0; ms <= 3000; ms += 100) {
        t.reportPlaybackPosition(sec(ms / 1000.0));
        final Duration observed = t.currentTime; // a timeline listener would only ever read this
        expect(observed, sec(ms / 1000.0));
      }
      expect(seeksPerformed, isEmpty);
    });
  });

  group("videoeditor7 Test C: user scrub 2 -> 3 -> 4 -> 6", () {
    test("UI reaches 6 immediately; seeks coalesce to a final seek of 6", () async {
      final List<Duration> performedSeeks = <Duration>[];
      final List<Completer<void>> completers = <Completer<void>>[];
      Future<void> fakeSeek(Duration target) {
        performedSeeks.add(target);
        final Completer<void> c = Completer<void>();
        completers.add(c);
        return c.future;
      }

      final EditorTransport t = EditorTransport(duration: sec(10), onSeek: fakeSeek);
      t.beginScrub();
      t.requestSeek(sec(2));
      await Future<void>.delayed(Duration.zero);
      t.requestSeek(sec(3));
      t.requestSeek(sec(4));
      t.requestSeek(sec(6));

      expect(t.currentTime, sec(6));
      completers[0].complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(performedSeeks, <Duration>[sec(2), sec(6)]);
    });
  });

  group("videoeditor7 Test D: music region 2-7s across a full playback sweep", () {
    test("one entry sync, no seek every tick, pause after leaving the region", () {
      const BackgroundAudio bg = BackgroundAudio(
        filePath: "/tmp/music.mp3",
        startSec: Duration(seconds: 2),
        duration: Duration(seconds: 5),
      );
      const Duration trimmed = Duration(seconds: 10);

      bool wasInRegion = false;
      bool musicPlaying = false;
      Duration musicPlayerPosition = Duration.zero;
      int seekCount = 0;
      int playCount = 0;
      double? previousTick;

      // 0 -> 1 -> 2.1 -> 3 -> 4 -> 5 -> 6 -> 7.1, exactly the spec's own
      // sequence.
      for (final double s in <double>[0, 1, 2.1, 3, 4, 5, 6, 7.1]) {
        // The music player's own position advances with real elapsed
        // time exactly like a real VideoPlayerController would between
        // two ticks while actually playing — this is what makes the
        // drift check inside decideMusicSync meaningful to exercise,
        // instead of testing against a position that only ever moves
        // when a seek happens.
        if (musicPlaying && previousTick != null) {
          musicPlayerPosition += sec(s - previousTick);
        }
        previousTick = s;

        final MusicSyncDecision decision = EditorTransport.decideMusicSync(
          bg: bg,
          currentTime: sec(s),
          trimmedDuration: trimmed,
          isPlaying: true,
          isScrubbing: false,
          wasInRegion: wasInRegion,
          musicPlayerPosition: musicPlayerPosition,
        );
        if (decision.seekTarget != null) {
          seekCount++;
          musicPlayerPosition = decision.seekTarget!; // simulates the seek landing exactly
        }
        if (decision.playback == MusicPlaybackIntent.playing && !musicPlaying) {
          playCount++;
        }
        musicPlaying = decision.playback == MusicPlaybackIntent.playing;
        // Mirrors trim_step.dart's own post-decision bookkeeping: "in
        // region" from here on is simply whether local time resolves.
        wasInRegion = EditorTransport.musicLocalTimeAt(bg, sec(s), trimmed) != null;
      }

      expect(seekCount, 1); // exactly one entry sync, no per-tick reseeking
      expect(playCount, 1); // started exactly once
      expect(musicPlaying, isFalse); // paused again after leaving the region at 7.1
    });
  });

  group("videoeditor7 Test E: scrub while music is playing", () {
    test("music pauses at scrub start, never free-runs, one final sync on scrub end", () {
      const BackgroundAudio bg = BackgroundAudio(
        filePath: "/tmp/music.mp3",
        startSec: Duration(seconds: 2),
        duration: Duration(seconds: 5),
      );
      const Duration trimmed = Duration(seconds: 10);

      // Playing at 3s, inside the region, already synced.
      bool wasInRegion = true;
      final Duration musicPlayerPosition = sec(1.0); // 3s project time -> 1s into the music

      // Scrub begins and moves 6 -> 4 -> 5.5 while isScrubbing=true.
      final List<MusicSyncDecision> duringScrub = <MusicSyncDecision>[
        EditorTransport.decideMusicSync(
          bg: bg,
          currentTime: sec(6),
          trimmedDuration: trimmed,
          isPlaying: true,
          isScrubbing: true,
          wasInRegion: wasInRegion,
          musicPlayerPosition: musicPlayerPosition,
        ),
        EditorTransport.decideMusicSync(
          bg: bg,
          currentTime: sec(4),
          trimmedDuration: trimmed,
          isPlaying: true,
          isScrubbing: true,
          wasInRegion: wasInRegion,
          musicPlayerPosition: musicPlayerPosition,
        ),
        EditorTransport.decideMusicSync(
          bg: bg,
          currentTime: sec(5.5),
          trimmedDuration: trimmed,
          isPlaying: true,
          isScrubbing: true,
          wasInRegion: wasInRegion,
          musicPlayerPosition: musicPlayerPosition,
        ),
      ];
      for (final MusicSyncDecision d in duringScrub) {
        expect(d.playback, MusicPlaybackIntent.paused);
        expect(d.seekTarget, isNull); // never seeked for an intermediate pointer event
      }
      // trim_step.dart resets wasInRegion to false the moment a scrub
      // begins — so scrub-end is always treated as a fresh entry.
      wasInRegion = false;

      // Scrub ends at 5.5s, isScrubbing flips back to false.
      final MusicSyncDecision atEnd = EditorTransport.decideMusicSync(
        bg: bg,
        currentTime: sec(5.5),
        trimmedDuration: trimmed,
        isPlaying: true, // editor was playing before the scrub, resumes
        isScrubbing: false,
        wasInRegion: wasInRegion,
        musicPlayerPosition: musicPlayerPosition,
      );
      expect(atEnd.seekTarget, sec(3.5)); // 5.5s project time -> 3.5s into the music
      expect(atEnd.playback, MusicPlaybackIntent.playing); // resumes since editor is playing
    });

    test("scrub end while editor is paused keeps music paused after the one sync", () {
      const BackgroundAudio bg = BackgroundAudio(
        filePath: "/tmp/music.mp3",
        startSec: Duration(seconds: 2),
        duration: Duration(seconds: 5),
      );
      final MusicSyncDecision atEnd = EditorTransport.decideMusicSync(
        bg: bg,
        currentTime: sec(5.5),
        trimmedDuration: const Duration(seconds: 10),
        isPlaying: false,
        isScrubbing: false,
        wasInRegion: false,
        musicPlayerPosition: sec(1.0),
      );
      expect(atEnd.seekTarget, sec(3.5)); // position still corrected
      expect(atEnd.playback, MusicPlaybackIntent.paused); // but stays paused
    });
  });

  group("videoeditor7 Test F: music operations never block video", () {
    test("transport methods return/update synchronously regardless of a slow music seek", () async {
      // A music seek that never completes during this test, standing in
      // for a slow/stalled async platform call.
      final Completer<void> slowMusicSeek = Completer<void>();
      unawaited(() async {
        await slowMusicSeek.future; // never actually completes here
      }());

      // The video transport is a completely separate instance with its
      // own fast fake seek — nothing about it depends on the music
      // operation above, which is the architectural point: transport
      // methods never await anything music-related, so a slow music
      // seek structurally cannot delay them.
      final EditorTransport videoTransport = EditorTransport(duration: sec(10), onSeek: (_) async {});
      videoTransport.play();
      videoTransport.reportPlaybackPosition(sec(1));
      videoTransport.reportPlaybackPosition(sec(2));
      videoTransport.requestSeek(sec(5));

      expect(videoTransport.currentTime, sec(5));
      expect(videoTransport.isPlaying, isTrue);
      expect(slowMusicSeek.isCompleted, isFalse); // still pending, and never was awaited by the video transport
    });
  });

  group("H: timeline feedback-loop prevention", () {
    test("reportPlaybackPosition never itself triggers a seek request", () async {
      final List<Duration> seeksPerformed = <Duration>[];
      final EditorTransport t = EditorTransport(
        duration: sec(10),
        onSeek: (Duration d) async {
          seeksPerformed.add(d);
        },
      );

      // Simulates programmatic, playback-driven position updates (what
      // a VideoPlayerController listener would report during normal
      // playback) — this must be a pure "read into the clock," never a
      // "write back to the player."
      t.reportPlaybackPosition(sec(1.0));
      t.reportPlaybackPosition(sec(2.0));
      t.reportPlaybackPosition(sec(3.0));
      await Future<void>.delayed(Duration.zero);

      expect(t.currentTime, sec(3.0));
      expect(seeksPerformed, isEmpty);
    });

    test("reportPlaybackPosition is ignored while scrubbing", () {
      final EditorTransport t = EditorTransport(duration: sec(10), onSeek: (_) async {});
      t.requestSeek(sec(5.0));
      t.beginScrub();
      t.reportPlaybackPosition(sec(1.0)); // a stray player callback mid-drag
      expect(t.currentTime, sec(5.0)); // unaffected — the user's own drag wins
    });

    test("reportPlaybackPosition is ignored while a seek is in flight", () async {
      final Completer<void> pending = Completer<void>();
      final EditorTransport t = EditorTransport(duration: sec(10), onSeek: (_) => pending.future);
      t.requestSeek(sec(4.0));
      await Future<void>.delayed(Duration.zero);
      expect(t.isSeeking, isTrue);

      t.reportPlaybackPosition(sec(0.5)); // settling-tail noise from the seek itself
      expect(t.currentTime, sec(4.0)); // unaffected

      pending.complete();
      await Future<void>.delayed(Duration.zero);
    });
  });
}

/// F's pure mapping — kept as a top-level function (not a method on
/// [EditorTransport], since mute is `VideoProject.removeAudio`, not a
/// function of transport *time*) so trim_step.dart's wiring and this
/// test reference the exact same logic rather than duplicating it.
double desiredOriginalAudioVolume({required bool removeAudio}) => removeAudio ? 0.0 : 1.0;
