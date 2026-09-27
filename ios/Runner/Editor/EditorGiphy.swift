import Foundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Mirror of android/.../editor/Giphy.kt: GIPHY search for the Stickers
// panel. The key comes from the app's env config (GIPHY_API_KEY, passed in
// by Flutter when the editor opens), never from source. A picked GIF is
// packed into the same kind of sprite sheet as the bundled stickers (frames
// every 50ms; PNG here — ImageIO can't write WebP on iOS 15) + a def JSON
// under Application Support/giphy, so preview, export and the "+"-relaunch
// treat it like any sticker.

enum GiphyConfig {
  nonisolated(unsafe) static var apiKey = ""
}

enum GiphyKind: String, CaseIterable {
  case stickers, gifs
  var label: String { self == .stickers ? "Stickers" : "GIFs" }
}

struct GiphyItem: Identifiable, Hashable {
  let id: String
  let title: String
  /// Small animated preview for the grid.
  let previewURL: URL
  /// The GIF actually imported (200px wide).
  let gifURL: URL
}

enum Giphy {
  private static let stepMs: Int64 = 50
  private static let maxFrames = 80
  private static let cols = 6

  /// Trending when `query` is blank. Rated pg-13 at most (CLAUDE.md section 31).
  static func search(kind: GiphyKind, query: String) async throws -> [GiphyItem] {
    let key = GiphyConfig.apiKey
    guard !key.isEmpty else { return [] }
    let q = query.trimmingCharacters(in: .whitespaces)
    var components = URLComponents(string: "https://api.giphy.com/v1/\(kind.rawValue)/\(q.isEmpty ? "trending" : "search")")!
    var items = [URLQueryItem(name: "api_key", value: key), URLQueryItem(name: "limit", value: "36"),
                 URLQueryItem(name: "rating", value: "pg-13")]
    if !q.isEmpty { items.append(URLQueryItem(name: "q", value: q)) }
    components.queryItems = items
    let (data, response) = try await URLSession.shared.data(from: components.url!)
    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      throw NSError(domain: "Giphy", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GIPHY HTTP \(http.statusCode)"])
    }
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let list = root["data"] as? [[String: Any]] else { return [] }
    return list.compactMap { o in
      guard let id = o["id"] as? String,
            let images = o["images"] as? [String: Any],
            let full = images["fixed_width"] as? [String: Any],
            let fullURL = (full["url"] as? String).flatMap(URL.init(string:)) else { return nil }
      let small = (images["fixed_width_small"] as? [String: Any])?["url"] as? String
      return GiphyItem(id: id, title: o["title"] as? String ?? "", previewURL: small.flatMap(URL.init(string:)) ?? fullURL,
                       gifURL: fullURL)
    }
  }

  private static let cache = NSCache<NSURL, NSData>()

  static func bytes(_ url: URL) async throws -> Data {
    if let cached = cache.object(forKey: url as NSURL) { return cached as Data }
    let (data, _) = try await URLSession.shared.data(from: url)
    cache.setObject(data as NSData, forKey: url as NSURL)
    return data
  }

  static var directory: URL {
    let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                             appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
    let dir = base.appendingPathComponent("giphy", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// Frames of a GIF with their delays (seconds).
  static func frames(of data: Data) -> [(CGImage, Double)] {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
    return (0..<CGImageSourceGetCount(source)).compactMap { i in
      guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { return nil }
      let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
      let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
      var delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
      if delay < 0.02 { delay = 0.1 }
      return (image, delay)
    }
  }

  /// Downloads `item` and packs it into a local sprite sheet; returns its sticker definition.
  static func importItem(_ item: GiphyItem) async throws -> StickerDef {
    let id = "giphy_\(item.id)"
    if let existing = StickerStore.shared.byId(id) { return existing }
    let data = try await bytes(item.gifURL)
    let decoded = frames(of: data)
    guard let first = decoded.first?.0 else {
      throw NSError(domain: "Giphy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't decode that GIF"])
    }
    let w = first.width
    let h = first.height
    let scale = min(1, 200 / Double(max(w, h)))
    let cw = max(1, Int((Double(w) * scale).rounded()))
    let ch = max(1, Int((Double(h) * scale).rounded()))
    let starts = decoded.reduce(into: [Double]()) { acc, f in acc.append((acc.last ?? 0) + f.1) }
    let total = starts.last ?? 0.1
    let count = decoded.count <= 1 ? 1 : min(maxFrames, max(1, Int((total * 1000) / Double(stepMs))))
    let rows = (count + cols - 1) / cols
    guard let ctx = CGContext(data: nil, width: cw * cols, height: ch * rows, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw NSError(domain: "Giphy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Out of memory"])
    }
    ctx.interpolationQuality = .high
    for f in 0..<count {
      let t = Double(f) * total / Double(count)
      // The frame showing at time t: the first whose end is after t.
      let index = starts.firstIndex { $0 > t } ?? (decoded.count - 1)
      let col = f % cols
      let row = f / cols
      // CGContext is y-up: row 0 at the top of the image.
      ctx.draw(decoded[index].0, in: CGRect(x: col * cw, y: (rows - 1 - row) * ch, width: cw, height: ch))
    }
    guard let sheet = ctx.makeImage() else {
      throw NSError(domain: "Giphy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Couldn't build the sticker"])
    }
    let file = directory.appendingPathComponent("\(id).png")
    guard let dest = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
      throw NSError(domain: "Giphy", code: 4, userInfo: [NSLocalizedDescriptionKey: "Couldn't save the sticker"])
    }
    CGImageDestinationAddImage(dest, sheet, nil)
    guard CGImageDestinationFinalize(dest) else {
      throw NSError(domain: "Giphy", code: 5, userInfo: [NSLocalizedDescriptionKey: "Couldn't save the sticker"])
    }
    let def = StickerDef(id: id, label: item.title.isEmpty ? "GIPHY" : item.title, file: file.path, frames: count,
                         cols: cols, size: max(cw, ch), durationMs: max(Int64(total * 1000), 100), w: cw, h: ch, local: true)
    StickerStore.shared.saveLocal(def)
    return def
  }
}

/// An animated GIF thumbnail (UIImageView with the GIF's frames).
struct AnimatedGifView: UIViewRepresentable {
  let url: URL

  final class Coordinator {
    var loadedURL: URL?
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> UIImageView {
    let view = UIImageView()
    view.contentMode = .scaleAspectFit
    view.clipsToBounds = true
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    return view
  }

  func updateUIView(_ view: UIImageView, context: Context) {
    guard context.coordinator.loadedURL != url else { return }
    context.coordinator.loadedURL = url
    view.image = nil
    let url = url
    Task {
      guard let data = try? await Giphy.bytes(url) else { return }
      let image: UIImage? = await Task.detached(priority: .utility) { () -> UIImage? in
        let frames = Giphy.frames(of: data)
        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames.map { UIImage(cgImage: $0.0) },
                                     duration: frames.reduce(0) { $0 + $1.1 })
      }.value
      await MainActor.run {
        if context.coordinator.loadedURL == url { view.image = image }
      }
    }
  }
}
