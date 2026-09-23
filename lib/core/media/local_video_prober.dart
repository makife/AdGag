/// Reads basic metadata (currently just duration) from a local video file
/// before it's uploaded, so the creation flow can decide whether a trim
/// step is needed (CLAUDE.md section 4/38).
abstract interface class LocalVideoProber {
  Future<Duration> probeDuration(String filePath);
}
