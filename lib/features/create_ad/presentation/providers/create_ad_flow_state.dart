import "../../../subjects/domain/ad_subject.dart";
import "../../domain/create_ad_step.dart";
import "../../domain/local_video_draft.dart";

final class CreateAdFlowState {
  const CreateAdFlowState({
    this.step = CreateAdStep.subject,
    this.subject,
    this.capturedDraft,
    this.finalDraft,
    this.caption = "",
    this.uploadProgress = 0,
    this.adId,
    this.errorMessage,
    this.processingStillPending = false,
  });

  final CreateAdStep step;
  final AdSubject? subject;

  /// The raw recorded/imported clip, before trimming — kept so the trim
  /// step has something to trim. Null once a [finalDraft] exists and no
  /// trim was needed.
  final LocalVideoDraft? capturedDraft;

  /// The clip that will actually be uploaded (either the capture directly,
  /// if it was already within [VideoConstraints], or the trimmed result).
  final LocalVideoDraft? finalDraft;

  final String caption;
  final double uploadProgress;
  final String? adId;
  final String? errorMessage;

  /// True if the upload succeeded but server-side processing hadn't
  /// finished by the time this flow stopped polling — a "still working on
  /// it" outcome, not a failure (CLAUDE.md section 19/39).
  final bool processingStillPending;

  CreateAdFlowState copyWith({
    CreateAdStep? step,
    AdSubject? subject,
    LocalVideoDraft? capturedDraft,
    LocalVideoDraft? finalDraft,
    String? caption,
    double? uploadProgress,
    String? adId,
    String? errorMessage,
    bool? processingStillPending,
  }) {
    return CreateAdFlowState(
      step: step ?? this.step,
      subject: subject ?? this.subject,
      capturedDraft: capturedDraft ?? this.capturedDraft,
      finalDraft: finalDraft ?? this.finalDraft,
      caption: caption ?? this.caption,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      adId: adId ?? this.adId,
      errorMessage: errorMessage ?? this.errorMessage,
      processingStillPending: processingStillPending ?? this.processingStillPending,
    );
  }
}
