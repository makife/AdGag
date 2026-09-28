import Foundation

/// The native editor's UI language — same contract as Android's EditorL10n.kt.
/// The Flutter app passes the language it is actually showing with every
/// openEditor call; strings are looked up by their ENGLISH text —
/// `tr("Cancel")`, `tr("Clip {0} · trim", n)` — in `AdGagL10n/editor.json`,
/// generated from `tool/l10n/editor_strings.py`. A missing translation just
/// shows the English text.
enum EditorL10n {
  private(set) static var language = "en"
  private static var table: [String: String] = [:]

  static func load(_ lang: String?) {
    let code = (lang?.isEmpty == false) ? lang! : "en"
    language = code
    guard code != "en",
          let url = Bundle.main.url(forResource: "editor", withExtension: "json", subdirectory: "AdGagL10n"),
          let data = try? Data(contentsOf: url),
          let all = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let t = all[code] as? [String: String]
    else {
      table = [:]
      return
    }
    table = t
  }

  static func t(_ en: String, _ args: [Any]) -> String {
    var s = table[en] ?? en
    for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\(i)}", with: "\(a)") }
    return s
  }
}

/// The editor's translation of `en` (English text as the key); `{0}`, `{1}`… are replaced by `args`.
func tr(_ en: String, _ args: Any...) -> String { EditorL10n.t(en, args) }
