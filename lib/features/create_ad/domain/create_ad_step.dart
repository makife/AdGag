/// Steps of the single creation engine (CLAUDE.md section 38): "Reuse the
/// same creation engine. Do not create three independent upload
/// implementations." AD THIS and Daily Ad reuse this same state machine,
/// just starting from [capture] with a subject already chosen (Phase E/F —
/// not wired yet, but this step list already has the seam for it).
enum CreateAdStep {
  subject,
  capture,
  trim,
  caption,
  publishing,
  success,
  failure,
}
