import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/video/video_providers.dart";
import "../../../feed/domain/ad.dart";
import "../../../feed/domain/ad_status.dart";
import "../../../feed/presentation/providers/feed_controller.dart";
import "../../../market/presentation/providers/market_providers.dart";
import "../../../subjects/domain/ad_subject.dart";
import "../../../subjects/presentation/providers/subject_providers.dart";
import "../../domain/create_ad_step.dart";
import "../../domain/local_video_draft.dart";
import "../../domain/video_constraints.dart";
import "draft_ad_providers.dart";
import "create_ad_flow_state.dart";

/// Drives the single creation engine described in CLAUDE.md section 38:
/// subject -> capture -> (trim if needed) -> caption -> publish -> upload
/// -> processing -> ready. AD THIS ([startAdThis]) reuses this same
/// engine, just entering past the subject step with the origin Ad's
/// subject and id already known. Daily Ad (Phase F) will do the same with
/// a `dailyChallengeId`.
final class CreateAdFlowController extends Notifier<CreateAdFlowState> {
  @override
  CreateAdFlowState build() => const CreateAdFlowState();

  Future<void> selectSubjectText(String text) async {
    final subject = await ref.read(subjectRepositoryProvider).getOrCreateSubject(text);
    state = state.copyWith(subject: subject, step: CreateAdStep.capture);
  }

  /// Entry point for AD THIS (CLAUDE.md section 9): subject is already
  /// known from the Ad being remixed, so the flow starts at capture.
  void startAdThis({required AdSubject subject, required String inspiredByAdId}) {
    state = CreateAdFlowState(
      subject: subject,
      inspiredByAdId: inspiredByAdId,
      step: CreateAdStep.capture,
    );
  }

  /// Entry point for "AD THIS SUBJECT" from a subject page (section 10) —
  /// subject preselected, but no lineage to a specific origin Ad.
  void startWithSubject(AdSubject subject) {
    state = CreateAdFlowState(subject: subject, step: CreateAdStep.capture);
  }

  /// Entry point for joining Today's Ad (CLAUDE.md section 11): subject
  /// and challenge id already known from the active challenge.
  void startDailyChallenge({required AdSubject subject, required String dailyChallengeId}) {
    state = CreateAdFlowState(
      subject: subject,
      dailyChallengeId: dailyChallengeId,
      step: CreateAdStep.capture,
    );
  }

  /// Called once a recording/import produces a local file. Always routes
  /// through the edit step (trim/speed/rotate/flip/audio) — even a clip
  /// already within [VideoConstraints] may still want those tools, not
  /// just ones that need trimming down.
  void onVideoCaptured(LocalVideoDraft draft) {
    state = state.copyWith(capturedDraft: draft, step: CreateAdStep.trim);
  }

  void onVideoTrimmed(LocalVideoDraft trimmed) {
    state = state.copyWith(finalDraft: trimmed, step: CreateAdStep.caption);
  }

  /// Discards the current capture and returns to record/import (the edit
  /// step's "Retake" action).
  void retake() {
    state = state.copyWith(step: CreateAdStep.capture);
  }

  void setCaption(String caption) {
    state = state.copyWith(caption: caption);
  }

  void backTo(CreateAdStep step) {
    state = state.copyWith(step: step);
  }

  Future<void> publish() async {
    final String? subjectId = state.subject?.id;
    final LocalVideoDraft? draft = state.finalDraft;
    if (subjectId == null || draft == null) {
      state = state.copyWith(
        step: CreateAdStep.failure,
        errorMessage: "Missing subject or video.",
      );
      return;
    }

    state = state.copyWith(step: CreateAdStep.publishing, uploadProgress: 0, errorMessage: null);

    try {
      final Ad draftAd = await ref.read(draftAdRepositoryProvider).createDraft(
            subjectId: subjectId,
            caption: state.caption.trim(),
            inspiredByAdId: state.inspiredByAdId,
            dailyChallengeId: state.dailyChallengeId,
          );
      state = state.copyWith(adId: draftAd.id);

      final session = await ref.read(videoServiceProvider).createUploadSession(draftAd.id);

      await ref.read(videoUploaderProvider).upload(
            uploadUrl: session.uploadUrl,
            filePath: draft.filePath,
            onProgress: (double progress) => state = state.copyWith(uploadProgress: progress),
          );

      await _pollUntilProcessed(draftAd.id);
    } catch (e) {
      state = state.copyWith(step: CreateAdStep.failure, errorMessage: "$e");
    }
  }

  Future<void> _pollUntilProcessed(String adId) async {
    const int maxAttempts = 30;
    const Duration interval = Duration(seconds: 2);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      await Future<void>.delayed(interval);
      final Ad ad = await ref.read(draftAdRepositoryProvider).getById(adId);

      switch (ad.status) {
        case AdStatus.ready:
          state = state.copyWith(step: CreateAdStep.success, processingStillPending: false);
          // Without this, a just-published Ad only shows up in Home/Market
          // after a cold restart happens to refetch these — the providers
          // otherwise keep serving whatever page they last fetched.
          ref.invalidate(feedControllerProvider);
          ref.invalidate(freshAdsProvider);
          ref.invalidate(trendingSubjectsProvider);
          return;
        case AdStatus.failed:
        case AdStatus.blocked:
        case AdStatus.deleted:
          state = state.copyWith(
            step: CreateAdStep.failure,
            errorMessage: "This one didn't make the campaign.",
          );
          return;
        case AdStatus.draft:
        case AdStatus.uploading:
        case AdStatus.processing:
          continue; // keep polling
      }
    }

    // Upload succeeded but processing is taking longer than we'll wait
    // here — not a failure, just not done yet (section 19/39).
    state = state.copyWith(step: CreateAdStep.success, processingStillPending: true);
  }

  void reset() {
    state = const CreateAdFlowState();
  }
}

final NotifierProvider<CreateAdFlowController, CreateAdFlowState> createAdFlowControllerProvider =
    NotifierProvider<CreateAdFlowController, CreateAdFlowState>(CreateAdFlowController.new);
