import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";

import "package:adgag/core/video/video_providers.dart";
import "package:adgag/core/video/video_service.dart";
import "package:adgag/core/video/video_upload_session.dart";
import "package:adgag/core/video/video_uploader.dart";
import "package:adgag/core/video/upload_cancel_token.dart";
import "package:adgag/features/create_ad/domain/create_ad_step.dart";
import "package:adgag/features/create_ad/domain/draft_ad_repository.dart";
import "package:adgag/features/create_ad/domain/local_video_draft.dart";
import "package:adgag/features/create_ad/presentation/providers/create_ad_flow_controller.dart";
import "package:adgag/features/create_ad/presentation/providers/draft_ad_providers.dart";
import "package:adgag/features/feed/domain/ad.dart";
import "package:adgag/features/feed/domain/ad_status.dart";
import "package:adgag/features/subjects/domain/ad_subject.dart";
import "package:adgag/features/subjects/domain/subject_repository.dart";
import "package:adgag/features/subjects/presentation/providers/subject_providers.dart";

class _FakeSubjectRepository implements SubjectRepository {
  @override
  Future<AdSubject> getOrCreateSubject(String text, {String locale = "en"}) async {
    return AdSubject(id: "subj1", canonicalKey: text.toLowerCase(), displayName: text, adsCount: 0);
  }

  @override
  Future<AdSubject?> getSubjectById(String id) async => null;
}

class _FakeDraftAdRepository implements DraftAdRepository {
  AdStatus nextStatus = AdStatus.ready;

  Map<String, dynamic> _row({required String id, required AdStatus status}) => <String, dynamic>{
        "id": id,
        "user_id": "u1",
        "subject_id": "subj1",
        "caption": null,
        "playback_id": null,
        "thumbnail_url": null,
        "duration_ms": null,
        "status": status.name,
        "inspired_by_ad_id": null,
        "daily_challenge_id": null,
        "view_count": 0,
        "sold_count": 0,
        "comment_count": 0,
        "share_count": 0,
        "ad_this_count": 0,
        "created_at": "2026-01-01T00:00:00Z",
        "published_at": null,
      };

  @override
  Future<Ad> createDraft({required String subjectId, String? caption}) async {
    return Ad.fromRow(_row(id: "ad1", status: AdStatus.draft));
  }

  @override
  Future<Ad> updateDraft({required String adId, String? subjectId, String? caption}) async {
    return Ad.fromRow(_row(id: adId, status: AdStatus.draft));
  }

  @override
  Future<void> deleteAd(String adId) async {}

  @override
  Future<Ad> getById(String adId) async => Ad.fromRow(_row(id: adId, status: nextStatus));
}

class _FakeVideoService implements VideoService {
  @override
  Future<VideoUploadSession> createUploadSession(String adId) async {
    return const VideoUploadSession(uploadUrl: "https://example.com/upload");
  }

  @override
  String playbackUrl(String playbackId) => "https://stream.mux.com/$playbackId.m3u8";

  @override
  String thumbnailUrl(String playbackId) => "https://image.mux.com/$playbackId/thumbnail.jpg";
}

class _FakeVideoUploader implements VideoUploader {
  @override
  Future<void> upload({
    required String uploadUrl,
    required String filePath,
    required void Function(double progress) onProgress,
    UploadCancelToken? cancelToken,
  }) async {
    onProgress(1.0);
  }
}

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: <Override>[
        subjectRepositoryProvider.overrideWithValue(_FakeSubjectRepository()),
        draftAdRepositoryProvider.overrideWithValue(_FakeDraftAdRepository()),
        videoServiceProvider.overrideWithValue(_FakeVideoService()),
        videoUploaderProvider.overrideWithValue(_FakeVideoUploader()),
      ],
    );
  });

  tearDown(() => container.dispose());

  test("subject -> capture -> caption -> publish reaches success", () async {
    final CreateAdFlowController controller = container.read(createAdFlowControllerProvider.notifier);

    await controller.selectSubjectText("Sock");
    expect(container.read(createAdFlowControllerProvider).step, CreateAdStep.capture);
    expect(container.read(createAdFlowControllerProvider).subject?.displayName, "Sock");

    controller.onVideoCaptured(
      const LocalVideoDraft(filePath: "/tmp/clip.mp4", duration: Duration(seconds: 5)),
    );
    expect(container.read(createAdFlowControllerProvider).step, CreateAdStep.caption);

    controller.setCaption("Some people are harder.");
    expect(container.read(createAdFlowControllerProvider).caption, "Some people are harder.");

    await controller.publish();
    final state = container.read(createAdFlowControllerProvider);
    expect(state.step, CreateAdStep.success);
    expect(state.processingStillPending, isFalse);
  });

  test("a clip longer than the max duration routes to the trim step", () {
    final CreateAdFlowController controller = container.read(createAdFlowControllerProvider.notifier);

    controller.onVideoCaptured(
      const LocalVideoDraft(filePath: "/tmp/long.mp4", duration: Duration(seconds: 25)),
    );

    final state = container.read(createAdFlowControllerProvider);
    expect(state.step, CreateAdStep.trim);
    expect(state.capturedDraft, isNotNull);
    expect(state.finalDraft, isNull);
  });

  test("publishing without a subject/video fails fast without a network call", () async {
    final CreateAdFlowController controller = container.read(createAdFlowControllerProvider.notifier);

    await controller.publish();

    final state = container.read(createAdFlowControllerProvider);
    expect(state.step, CreateAdStep.failure);
    expect(state.errorMessage, isNotNull);
  });
}
