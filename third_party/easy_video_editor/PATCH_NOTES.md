# Why this is vendored

This is `easy_video_editor` 0.1.6 (pub.dev), unmodified except for three
iOS Swift files that fail to compile on newer Swift toolchains (confirmed
on the GitHub Actions `macos-15` runner, used by `.github/workflows/ios-build.yml`
since this project has no local Mac):

```
Swift Compiler Error (Xcode): Cannot find type 'DispatchWorkItem' in scope
  ios/easy_video_editor/Sources/easy_video_editor/utils/OperationManager.swift:3
Swift Compiler Error (Xcode): Cannot find 'DispatchQueue' in scope
  ios/easy_video_editor/Sources/easy_video_editor/utils/OperationManager.swift:4
```

Root cause: `OperationManager.swift`, `handler/MergeVideosCommand.swift`,
and `utils/ProgressManager.swift` use `DispatchWorkItem`/`DispatchQueue`
without ever importing `Dispatch` — this apparently worked on older Xcode/
Swift toolchains (where `Foundation` implicitly re-exported `Dispatch` on
Apple platforms) but fails on the newer one this runner uses.

Confirmed via the package's own real 0.1.6 tarball (downloaded from
`https://pub.dev/api/archives/easy_video_editor-0.1.6.tar.gz`, not
assumed) — none of the three files import `Dispatch` or `Foundation` at
all. Two open, unmerged upstream PRs
([#48](https://github.com/iawtk2302/easy_video_editor/pull/48),
[#50](https://github.com/iawtk2302/easy_video_editor/pull/50)) address a
*related but different* Swift 6 issue (self-referencing `lazy var`
initializers) — neither actually adds the missing `Dispatch` import, and
neither has been merged or released as a new pub.dev version as of this
patch (2026-09-25).

**Fix applied**: added `import Dispatch` to the top of all three files.
No other changes.

**Remove this vendored copy once either**:
- a new `easy_video_editor` version ships on pub.dev with this fixed, or
- one of the two PRs above (or an equivalent fix) is merged and released,

by deleting `third_party/easy_video_editor/` and the
`dependency_overrides` entry in the root `pubspec.yaml`, then bumping the
regular `easy_video_editor` version constraint if needed.
