import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../../../core/video/video_providers.dart";
import "../../../feed/domain/ad.dart";
import "../../../feed/domain/ad_status.dart";
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

  /// Called once a recording/import produces a local file. Skips the trim
  /// step entirely when the clip is already within
  /// [VideoConstraints] — "Editing must remain intentionally lightweight"
  /// (section 4).
  void onVideoCaptured(LocalVideoDraft draft) {
    if (draft.isWithinConstraints) {
      state = state.copyWith(finalDraft: draft, step: CreateAdStep.caption);
    } else {
      state = state.copyWith(capturedDraft: draft, step: CreateAdStep.trim);
    }
  }

  void onVideoTrimmed(LocalVideoDraft trimmed) {
    state = state.copyWith(finalDraft: trimmed, step: CreateAdStep.caption);
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
