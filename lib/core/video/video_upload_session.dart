/// Returned by [VideoService.createUploadSession]: everything the client
/// needs to PUT a video file directly to the provider (CLAUDE.md section
/// 18). Never contains provider credentials — those stay server-side.
final class VideoUploadSession {
  const VideoUploadSession({required this.uploadUrl});

  final String uploadUrl;
}
