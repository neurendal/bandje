import AppKit
import AVFoundation
import Foundation
import SwiftUI

/// "Deel als webpagina…": one self-contained `.html` for a recording, to send to anyone. The player,
/// the transcript (click a turn to listen), the summaries as tabs, the audio embedded; Bandje's
/// logo and a link to band.je. Static: every text is escaped, no external resources, and no way
/// back into the app (no `bandje://` links, no paths of this Mac).
enum WebExport {
    struct Summary: Equatable {
        var name: String
        var markdown: String
    }

    /// The tab of a summary: "Samenvatting" (as on the iPhone); with several summaries the template follows.
    static func tabTitle(_ template: String, count: Int) -> String {
        let word = tr("summary.tab", "Samenvatting")
        return count > 1 ? "\(word) · \(template)" : word
    }

    /// The only URL in our code besides the About links (CLAUDE.md limit 1, owner 2026-11-06).
    static let siteURL = "https://band.je"

    /// Summaries next to `json`: `<base> <word> <template>.md` (any word, so a summary made in
    /// another menu language is found too). Newest first.
    static func summaries(for json: URL) -> [Summary] {
        let base = json.deletingPathExtension().lastPathComponent
        let folder = json.deletingLastPathComponent()
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        // Newest first (as on the iPhone): a new summary with another template is the one you see.
        func date(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        return files.sorted { date($0) > date($1) }.compactMap { url -> Summary? in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "md", name.hasPrefix(base + " "),
                  let md = Files.readString(url) else { return nil }
            let rest = name.dropFirst(base.count + 1)
            let template = rest.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? String(rest)
            return Summary(name: template, markdown: Summaries.body(ofDocument: md))
        }
    }

    /// Writes the page for the transcript at `json` to a temporary file named after the recording,
    /// for the share sheet. `compact`: the audio as mono speech at 32 kbit/s (~19 MB per hour).
    static func export(json: URL, compact: Bool) async throws -> URL {
        let t = try TranscriptWriter.read(json: json)
        let folder = json.deletingLastPathComponent()
        var audio: (base64: String, type: String)?
        // Only a file in this folder (a synced json could name any path), else the folder's own audio.
        let named = t.audioFile.map { folder.appendingPathComponent(URL(fileURLWithPath: $0).lastPathComponent) }
        if let file = named.flatMap({ FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }) ?? Library.audioFile(in: folder) {
            try await ICloudSync.ensureDownloaded(file)
            let data = compact ? try await compactAudio(file) : try Files.read(file)
            audio = (data.base64EncodedString(), compact ? "audio/mp4" : mimeType(file.pathExtension))
        }
        let logo = OutputLocation.bundledLogo.flatMap { try? Data(contentsOf: $0) }?.base64EncodedString()
        let html = page(t, summaries: summaries(for: json), audio: audio, logoBase64: logo)
        removeOldPages()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Bandje-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(OutputLocation.safeName(json.deletingPathExtension().lastPathComponent) + ".html")
        try Data(html.utf8).write(to: url, options: .atomic)
        return url
    }

    static func mimeType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "m4a", "mp4", "m4b", "aac": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "wav": "audio/wav"
        case "aif", "aiff", "aifc": "audio/aiff"
        case "flac": "audio/flac"
        default: "audio/\(ext.lowercased())"
        }
    }

    /// Pages made more than a day ago (the share sheet has long copied them).
    static func removeOldPages() {
        let tmp = FileManager.default.temporaryDirectory
        let old = Date().addingTimeInterval(-86_400)
        for item in (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: [.creationDateKey])) ?? []
        where item.lastPathComponent.hasPrefix("Bandje-share-") {
            if let created = try? item.resourceValues(forKeys: [.creationDateKey]).creationDate, created < old {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    /// The recording as AAC mono 22.05 kHz at 32 kbit/s: speech stays clear, an hour is ~14 MB.
    /// Written with ExtAudioFile: AVAudioFile ignores the bitrate (it gives ~58 kbit/s).
    static func compactAudio(_ source: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let input = try AVAudioFile(forReading: source)
            let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22_050, channels: 1, interleaved: false)!
            guard let converter = AVAudioConverter(from: input.processingFormat, to: mono) else { throw CocoaError(.fileWriteUnknown) }
            // Mix both channels: without this the converter keeps only the left one (me), not the other side.
            converter.downmix = true
            let target = FileManager.default.temporaryDirectory.appendingPathComponent("compact-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: target) }

            var aac = AudioStreamBasicDescription(mSampleRate: 22_050, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
                                                  mBytesPerPacket: 0, mFramesPerPacket: 1024, mBytesPerFrame: 0,
                                                  mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
            var ref: ExtAudioFileRef?
            var status = ExtAudioFileCreateWithURL(target as CFURL, kAudioFileM4AType, &aac, nil, AudioFileFlags.eraseFile.rawValue, &ref)
            guard status == noErr, let out = ref else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            var disposed = false
            defer { if !disposed { ExtAudioFileDispose(out) } }
            var client = mono.streamDescription.pointee
            status = ExtAudioFileSetProperty(out, kExtAudioFileProperty_ClientDataFormat,
                                             UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client)
            guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            // The bitrate is a property of the file's encoder; after changing it the file must re-read its config.
            var encoder: AudioConverterRef?
            var size = UInt32(MemoryLayout<AudioConverterRef?>.size)
            if ExtAudioFileGetProperty(out, kExtAudioFileProperty_AudioConverter, &size, &encoder) == noErr, let encoder {
                var bitrate: UInt32 = 32_000
                AudioConverterSetProperty(encoder, kAudioConverterEncodeBitRate, UInt32(MemoryLayout<UInt32>.size), &bitrate)
                var config: CFArray? = nil
                _ = withUnsafeMutablePointer(to: &config) {
                    ExtAudioFileSetProperty(out, kExtAudioFileProperty_ConverterConfig, UInt32(MemoryLayout<CFArray?>.size), $0)
                }
            }

            let inBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 32_768)!
            let ratio = mono.sampleRate / input.processingFormat.sampleRate
            // `read` throws at the end of the file instead of returning 0 frames: stop before it.
            while input.framePosition < input.length {
                try input.read(into: inBuffer)
                if inBuffer.frameLength == 0 { break }
                let outBuffer = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(Double(inBuffer.frameLength) * ratio) + 1024)!
                var fed = false
                var error: NSError?
                converter.convert(to: outBuffer, error: &error) { _, state in
                    if fed { state.pointee = .noDataNow; return nil }
                    fed = true
                    state.pointee = .haveData
                    return inBuffer
                }
                if let error { throw error }
                if outBuffer.frameLength > 0 {
                    status = ExtAudioFileWrite(out, outBuffer.frameLength, outBuffer.audioBufferList)
                    guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
                }
            }
            status = ExtAudioFileDispose(out)  // finishes the file
            disposed = true
            guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            return try Data(contentsOf: target)
        }.value
    }

    // MARK: PDF

    /// The transcript as a PDF (A4, as on the iPhone): Band●je top left and the cassette top right
    /// above a red rule, the title, the header lines, then per turn the time and speaker in grey with
    /// the text under it. Every page has a footer: made with Band·je, and "n / N". Made on this Mac
    /// when shared; `cassette` is rendered by the caller (SwiftUI, main actor).
    static func pdf(_ t: Transcript, locale: Locale = TranscriptWriter.appLocale, cassette: NSImage? = nil) -> Data {
        let text = NSMutableAttributedString()
        func add(_ string: String, _ font: NSFont, _ color: NSColor = .black, after: CGFloat = 0) {
            let style = NSMutableParagraphStyle()
            style.paragraphSpacing = after
            style.lineSpacing = 2
            text.append(NSAttributedString(string: string + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        }
        let grey = NSColor(white: 0.4, alpha: 1)
        add(t.title, .systemFont(ofSize: 20, weight: .bold), after: 6)
        let header = TranscriptWriter.headerLines(t, locale: locale)
        for (i, line) in header.enumerated() {
            add(line, .systemFont(ofSize: 10), grey, after: i == header.count - 1 ? 18 : 1)
        }
        let turns = TranscriptWriter.joinConsecutive(t.segments)
        if turns.isEmpty {
            add(tr("transcript.noSpeech", "Geen spraak herkend."),
                NSFontManager.shared.convert(.systemFont(ofSize: 11), toHaveTrait: .italicFontMask), grey)
        }
        for seg in turns {
            let time = TranscriptWriter.shortClock(seg.start)
            add(seg.speaker.isEmpty ? time : "\(time) · \(t.name(of: seg.speaker))", .systemFont(ofSize: 10.5, weight: .semibold), grey, after: 2)
            add(seg.text, .systemFont(ofSize: 11.5), after: 12)
        }

        let page = CGRect(x: 0, y: 0, width: 595, height: 842), margin: CGFloat = 56
        let brandBand: CGFloat = 54, footer: CGFloat = 30  // the brand above the title (page 1), the footer line
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var containers: [NSTextContainer] = []
        repeat {
            let top = containers.isEmpty ? brandBand : 0
            let container = NSTextContainer(size: CGSize(width: page.width - 2 * margin, height: page.height - 2 * margin - top - footer))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            layout.ensureLayout(for: container)
        } while NSMaxRange(layout.glyphRange(for: containers.last!)) < layout.numberOfGlyphs && containers.count < 2000

        let data = NSMutableData()
        var box = page
        let info = [kCGPDFContextTitle: t.title, kCGPDFContextCreator: "Band·je"] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &box, info) else { return Data() }
        let accent = NSColor(srgbRed: 0xD2 / 255, green: 0x44 / 255, blue: 0x2A / 255, alpha: 1)
        let navy = NSColor(srgbRed: 0x26 / 255, green: 0x2B / 255, blue: 0x4F / 255, alpha: 1)
        for (n, container) in containers.enumerated() {
            pdf.beginPDFPage(nil)
            // Text is laid out top-down: draw in a flipped context.
            pdf.translateBy(x: 0, y: page.height)
            pdf.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)
            if n == 0 {
                drawWordmark(at: CGPoint(x: margin, y: margin), size: 22)
                if let cassette {
                    let w: CGFloat = 48, h = w * cassette.size.height / max(1, cassette.size.width)
                    cassette.draw(in: CGRect(x: page.width - margin - w, y: margin - 2, width: w, height: h),
                                  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                accent.setFill()
                CGRect(x: margin, y: margin + brandBand - 14, width: page.width - 2 * margin, height: 1.5).fill()
            }
            let range = layout.glyphRange(for: container)
            let origin = CGPoint(x: margin, y: margin + (n == 0 ? brandBand : 0))
            layout.drawBackground(forGlyphRange: range, at: origin)
            layout.drawGlyphs(forGlyphRange: range, at: origin)
            // Footer: where it was made, and the page.
            let y = page.height - margin + 4
            NSColor(white: 0.85, alpha: 1).setFill()
            CGRect(x: margin, y: y - 8, width: page.width - 2 * margin, height: 0.5).fill()
            let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8.5, weight: .medium), .foregroundColor: navy]
            NSAttributedString(string: tr("transcript.madeWith", "Opgenomen met Band·je · band.je"), attributes: small)
                .draw(at: CGPoint(x: margin, y: y))
            let number = NSAttributedString(string: "\(n + 1) / \(containers.count)", attributes: small)
            number.draw(at: CGPoint(x: page.width - margin - number.size().width, y: y))
            NSGraphicsContext.restoreGraphicsState()
            pdf.endPDFPage()
        }
        pdf.closePDF()
        return data as Data
    }

    /// "Band●je" in bold black, the dot drawn as the record mark (a red disc with a ring and a
    /// centre cut out, as on band.je), in the current flipped context with its top left at `origin`.
    private static func drawWordmark(at origin: CGPoint, size: CGFloat) {
        let font = NSFont.systemFont(ofSize: size, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black, .kern: -0.01 * size]
        let band = NSAttributedString(string: "Band", attributes: attrs), je = NSAttributedString(string: "je", attributes: attrs)
        band.draw(at: origin)
        let d = size * 0.48, gap = size * 0.05
        let baseline = origin.y + font.ascender
        let dot = CGRect(x: origin.x + band.size().width + gap, y: baseline - d + size * 0.02, width: d, height: d)
        let path = NSBezierPath()
        for f in [1, 0.92, 0.84, 0.3] as [CGFloat] {
            path.appendOval(in: dot.insetBy(dx: d / 2 * (1 - f), dy: d / 2 * (1 - f)))
        }
        path.windingRule = .evenOdd
        NSColor(srgbRed: 0xD2 / 255, green: 0x44 / 255, blue: 0x2A / 255, alpha: 1).setFill()
        path.fill()
        je.draw(at: CGPoint(x: dot.maxX + gap, y: origin.y))
    }

    /// The small cassette for the PDF, rendered light (the PDF is white paper).
    @MainActor static func pdfCassette() -> NSImage? {
        let renderer = ImageRenderer(content: CassetteView(state: CassetteState()).frame(width: 64).environment(\.colorScheme, .light))
        renderer.scale = 4
        return renderer.nsImage
    }

    // MARK: HTML

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// `mm:ss` or `h:mm:ss` to seconds.
    static func seconds(_ clock: String) -> Int? {
        let p = clock.split(separator: ":").compactMap { Int($0) }
        guard p.count == clock.split(separator: ":").count, (2...3).contains(p.count), p.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return p.reduce(0) { $0 * 60 + $1 }
    }

    /// Bold, italic, code and times (`[03:12]`) in an already escaped line.
    static func inline(_ escaped: String) -> String {
        var s = escaped
        let rules: [(String, String)] = [
            (#"\*\*(.+?)\*\*"#, "<strong>$1</strong>"),
            (#"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#, "<em>$1</em>"),
            (#"(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)"#, "<em>$1</em>"),
            (#"`([^`]+)`"#, "<code>$1</code>"),
        ]
        for (pattern, template) in rules {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        // Times in brackets, as the transcript lines give them to the model, become links into the
        // audio. A bare "10:30" is more often a clock time ("om 10:30") and stays text.
        let regex = try! NSRegularExpression(pattern: #"\[(\d{1,2}:\d{2}(?::\d{2})?)\]"#)
        var out = ""
        var last = s.startIndex
        for m in regex.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let whole = Range(m.range, in: s), let r = Range(m.range(at: 1), in: s),
                  let secs = seconds(String(s[r])) else { continue }
            out += s[last..<whole.lowerBound] + "<a class=\"t\" data-t=\"\(secs)\">\(s[r])</a>"
            last = whole.upperBound
        }
        return out + s[last...]
    }

    /// The Markdown the model writes (headings, bullets, numbered lists, paragraphs) as HTML.
    static func markdown(_ md: String) -> String {
        var out = ""
        var list: String?
        var paragraph: [String] = []
        func closeParagraph() { if !paragraph.isEmpty { out += "<p>" + paragraph.joined(separator: "<br>") + "</p>\n"; paragraph = [] } }
        func closeList() { if let l = list { out += "</\(l)>\n"; list = nil } }
        for raw in md.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { closeParagraph(); closeList(); continue }
            if let m = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                closeParagraph(); closeList()
                let level = min(4, max(2, line[m].filter { $0 == "#" }.count + 1))
                out += "<h\(level)>" + inline(escape(String(line[m.upperBound...]))) + "</h\(level)>\n"
            } else if let m = line.range(of: #"^([-*•]|\d+[.)])\s+"#, options: .regularExpression) {
                closeParagraph()
                let kind = line.first!.isNumber ? "ol" : "ul"
                if list != kind { closeList(); out += "<\(kind)>\n"; list = kind }
                out += "<li>" + inline(escape(String(line[m.upperBound...]))) + "</li>\n"
            } else if line.range(of: #"^(-{3,}|\*{3,})$"#, options: .regularExpression) != nil {
                closeParagraph(); closeList(); out += "<hr>\n"
            } else {
                closeList()
                paragraph.append(inline(escape(line)))
            }
        }
        closeParagraph(); closeList()
        return out
    }

    /// The page for transcript `t`: Bandje's logo and name, the player with the audio embedded,
    /// a tab per summary and the transcript (click a turn to listen), and the Bandje footer.
    static func page(_ t: Transcript, summaries: [Summary], audio: (base64: String, type: String)?, logoBase64: String?,
                     select: String? = nil, locale: Locale = TranscriptWriter.appLocale) -> String {
        let display = TranscriptWriter.displayTitle(t.title, locale: locale)
        let title = display == t.title ? t.title : tr("transcript.title", "Opname %@", display)
        let labels = t.speakerLabels
        var tabs: [(id: String, name: String, body: String)] = []
        for (i, s) in summaries.enumerated() {
            tabs.append(("s\(i)", tabTitle(s.name, count: summaries.count), "<article class=\"summary\">\n" + markdown(s.markdown) + "</article>"))
        }
        let joined = TranscriptWriter.joinConsecutive(t.segments)
        var turns = ""
        for (i, seg) in joined.enumerated() {
            let n = (labels.firstIndex(of: seg.speaker) ?? 0) % 6
            let end = i + 1 < joined.count ? joined[i + 1].start : max(seg.end, t.duration)
            turns += "<div class=\"turn c\(n)\" data-start=\"\(seg.start)\" data-end=\"\(end)\">"
                + "<a class=\"t\" data-t=\"\(seg.start)\">\(TranscriptWriter.shortClock(seg.start))</a>"
                + "<span class=\"who\">\(escape(t.name(of: seg.speaker)))</span>"
                + "<p>\(escape(seg.text))</p></div>\n"
        }
        if joined.isEmpty { turns = "<p class=\"muted\">\(escape(tr("transcript.noSpeech", "Geen spraak herkend.")))</p>" }
        tabs.append(("transcript", tr("player.transcript", "Transcript"), "<section class=\"turns\">\n" + turns + "</section>"))

        let active = select.flatMap { name in summaries.firstIndex { $0.name == name }.map { "s\($0)" } }
            ?? (summaries.isEmpty ? "transcript" : tabs[0].id)
        let tabButtons = tabs.map { "<button role=\"tab\" data-tab=\"\($0.id)\"\($0.id == active ? " aria-selected=\"true\"" : "")>\(escape($0.name))</button>" }.joined()
        let panels = tabs.map { "<div role=\"tabpanel\" id=\"\($0.id)\"\($0.id == active ? "" : " hidden")>\n\($0.body)\n</div>" }.joined(separator: "\n")
        let logo = logoBase64.map { "<img class=\"logo\" alt=\"Band·je\" src=\"data:image/png;base64,\($0)\">" } ?? ""
        // Mail and Files previews run no scripts: then the page says where it does work.
        let player = audio.map { "<audio id=\"audio\" controls preload=\"metadata\" src=\"data:\($0.type);base64,\($0.base64)\"></audio>" }
            .map { $0 + "\n<noscript><p class=\"muted\">" + escape(tr("export.noscript", "Open deze pagina in een browser, zoals Safari, om te luisteren en het transcript te volgen.")) + "</p></noscript>" } ?? ""
        let lang = locale.language.languageCode?.identifier ?? "nl"
        // The browser tab and bookmarks show the cassette.
        let icons = logoBase64.map { "<link rel=\"icon\" type=\"image/png\" href=\"data:image/png;base64,\($0)\">\n<link rel=\"apple-touch-icon\" href=\"data:image/png;base64,\($0)\">\n" } ?? ""
        let facts = TranscriptWriter.headerLines(t, locale: locale).first.map { String($0.dropFirst(2)) } ?? ""

        return """
        <!doctype html>
        <html lang="\(lang)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(title)) · Band·je</title>
        \(icons)<style>\(css)</style>
        </head>
        <body>
        <header>
        <div class="wrap">
        <div class="brand">\(logo)<span>Band·je</span></div>
        <h1>\(escape(title))</h1>
        <p class="muted">\(escape(facts))</p>
        \(player)
        <nav role="tablist">\(tabButtons)</nav>
        </div>
        </header>
        <main>
        \(panels)
        </main>
        <footer>
        <div class="wrap">
        \(logo)<p><strong>\(escape(tr("export.tagline", "Band·je neemt je gesprekken op en zet ze om in tekst.")))</strong>
        \(escape(tr("export.made", "Alles op je eigen apparaat: geen tokens, supersnel, met wie wat zei, in 25 talen.")))
        <a href="\(siteURL)">band.je</a></p>
        </div>
        </footer>
        <script>\(script)</script>
        </body>
        </html>

        """
    }

    private static let css = """
    :root{--bg:#fbfaf7;--fg:#1d1b18;--muted:#6b665e;--line:#e4e0d8;--card:#fff;--accent:#c4462b;--hl:#fff1d6;
    --c0:#c4462b;--c1:#2f6f9f;--c2:#3c8a4a;--c3:#8a5bb0;--c4:#b07a1c;--c5:#2a8a8a}
    @media (prefers-color-scheme:dark){:root{--bg:#1b1a18;--fg:#ece8e1;--muted:#a39d93;--line:#34312d;--card:#24221f;
    --accent:#ef7a5c;--hl:#3a3222;--c0:#ef7a5c;--c1:#7db4e0;--c2:#86c98f;--c3:#c4a0e6;--c4:#e0b45c;--c5:#6fcfcf}}
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.55 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
    header{position:sticky;top:0;z-index:2;background:var(--bg);border-bottom:1px solid var(--line);padding:16px 16px 0}
    .wrap,main{max-width:760px;margin-left:auto;margin-right:auto}
    .head{display:flex;gap:14px;align-items:center}
    .logo{width:28px;height:28px;border-radius:7px}
    h1{font-size:20px;margin:0;line-height:1.3}
    .muted{color:var(--muted);margin:2px 0 0;font-size:14px}
    .brand{display:flex;gap:8px;align-items:center;font-weight:700;color:var(--accent);margin-bottom:8px}
    footer{border-top:1px solid var(--line);padding:22px 16px 48px;color:var(--muted);font-size:14px}
    footer .wrap{display:flex;gap:14px;align-items:flex-start}footer .logo{width:40px;height:40px;border-radius:9px;flex:none}
    footer p{margin:0}footer strong{display:block;color:var(--fg);font-size:15px;margin-bottom:2px}
    footer a{color:var(--accent);font-weight:600;text-decoration:none}footer a:hover{text-decoration:underline}
    audio{display:block;width:100%;margin:14px auto 4px}
    nav{display:flex;gap:4px;overflow-x:auto;margin-top:10px}
    nav button{font:inherit;font-size:14px;border:0;background:none;color:var(--muted);padding:8px 12px;border-bottom:2px solid transparent;cursor:pointer;white-space:nowrap}
    nav button[aria-selected=true]{color:var(--fg);border-bottom-color:var(--accent);font-weight:600}
    main{padding:8px 16px 64px;box-sizing:content-box}
    .summary h2,.summary h3,.summary h4{margin:26px 0 6px;font-size:17px}
    .summary h3,.summary h4{font-size:16px}
    .summary ul,.summary ol{padding-left:22px;margin:6px 0}
    .summary li{margin:3px 0}
    .summary p{margin:6px 0}
    a.t{color:var(--accent);text-decoration:none;font-variant-numeric:tabular-nums;cursor:pointer}
    a.t:hover{text-decoration:underline}
    .turn{display:grid;grid-template-columns:52px 1fr;column-gap:12px;padding:10px 10px;border-radius:10px;cursor:pointer}
    .turn:hover{background:var(--card)}
    .turn.now{background:var(--hl)}
    .turn a.t{grid-row:span 2;font-size:13px;padding-top:2px}
    .who{font-weight:600;font-size:14px}
    .turn p{margin:2px 0 0}
    .c0 .who{color:var(--c0)}.c1 .who{color:var(--c1)}.c2 .who{color:var(--c2)}.c3 .who{color:var(--c3)}.c4 .who{color:var(--c4)}.c5 .who{color:var(--c5)}
    dl.info{display:grid;grid-template-columns:max-content 1fr;gap:6px 18px;margin-top:20px}
    dt{color:var(--muted)}dd{margin:0}
    @media (max-width:520px){.turn{grid-template-columns:1fr}.turn a.t{grid-row:auto}}
    """

    private static let script = """
    const audio=document.getElementById('audio');
    document.querySelectorAll('nav button').forEach(b=>b.addEventListener('click',()=>{
      document.querySelectorAll('nav button').forEach(x=>x.removeAttribute('aria-selected'));
      b.setAttribute('aria-selected','true');
      document.querySelectorAll('[role=tabpanel]').forEach(p=>p.hidden=p.id!==b.dataset.tab);
    }));
    function play(t){if(!audio)return;audio.currentTime=t;audio.play();}
    document.addEventListener('click',e=>{
      const a=e.target.closest('a.t');
      if(a){e.preventDefault();play(+a.dataset.t);return;}
      const turn=e.target.closest('.turn');
      if(turn&&!window.getSelection().toString())play(+turn.dataset.start);
    });
    const turns=[...document.querySelectorAll('.turn')];
    let current=null;
    if(audio)audio.addEventListener('timeupdate',()=>{
      const t=audio.currentTime;
      const now=turns.find(x=>t>=+x.dataset.start&&t<+x.dataset.end)||null;
      if(now===current)return;
      if(current)current.classList.remove('now');
      current=now;
      if(now){now.classList.add('now');
        if(!document.getElementById('transcript').hidden){const r=now.getBoundingClientRect();
          if(r.top<160||r.bottom>innerHeight)now.scrollIntoView({block:'center',behavior:'smooth'});}}
    });
    """
}

/// The words that go with a shared file (Mail's body and the title as subject; Messages and Notes
/// get them too), in the app's language: what it is, which recording, and a small closing note
/// "Opgenomen met Band·je" with Band·je linked to band.je (owner, 2026-11-07; `WebExport.siteURL`, the
/// shared page's own link, so no other URL is added).
enum ShareText {
    enum Kind { case audio, transcript, webPage }

    static func intro(_ kind: Kind, title: String, date: Date, locale: Locale = TranscriptWriter.appLocale) -> String {
        let day = date.formatted(Date.FormatStyle.dateTime.day().month(.wide).year().locale(locale))
        return switch kind {
        case .audio: tr("share.audio", "Hierbij de opname „%1$@” van %2$@.", title, day)
        case .transcript: tr("share.transcript", "Hierbij het transcript van „%1$@” van %2$@.", title, day)
        case .webPage: tr("share.webPage", "Hierbij de opname „%1$@” van %2$@, met het transcript. Open het bestand in je browser om te luisteren en mee te lezen.", title, day)
        }
    }

    /// The text: the intro, an empty line, and the note in a small font with "Band·je" as a link.
    static func body(_ kind: Kind, title: String, date: Date, locale: Locale = TranscriptWriter.appLocale) -> NSAttributedString {
        let text = NSMutableAttributedString(string: intro(kind, title: title, date: date, locale: locale) + "\n\n")
        let note = tr("share.madeWith", "Opgenomen met %@", "Band·je")
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                                                    .foregroundColor: NSColor.secondaryLabelColor]
        let start = text.length
        text.append(NSAttributedString(string: note, attributes: small))
        let name = (note as NSString).range(of: "Band·je")
        if name.location != NSNotFound, let url = URL(string: WebExport.siteURL) {
            text.addAttribute(.link, value: url, range: NSRange(location: start + name.location, length: name.length))
        }
        return text
    }

    /// A copy of each file in the temporary folder (APFS clones it, so even long audio is instant).
    /// Shared from the recordings folder (iCloud Drive), macOS offered the file as an iCloud link and
    /// Mail left out the text; the PDF and web page, made in the temporary folder, kept it.
    /// Audio still in iCloud is downloaded first.
    static func localCopies(_ files: [URL]) async throws -> [URL] {
        let temp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        var out: [URL] = []
        for file in files {
            if file.standardizedFileURL.path.hasPrefix(temp) { out.append(file); continue }
            try await ICloudSync.ensureDownloaded(file)
            let copy = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share/\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let copy = folder.appendingPathComponent(file.lastPathComponent)
                try Files.copy(file, to: copy)
                return copy
            }.value
            out.append(copy)
        }
        return out
    }

    /// Shows the share sheet for `files` with `image` (else the app icon) and `title` as the preview, the text as
    /// an extra item, and the title as the subject for Mail.
    @MainActor static func show(_ files: [URL], kind: Kind, title: String, date: Date, image: NSImage? = nil,
                                relativeTo rect: NSRect, of view: NSView) {
        let previews: [Any] = files.map { NSPreviewRepresentingActivityItem(item: $0, title: title, image: image ?? NSApp.applicationIconImage, icon: nil) }
        let picker = NSSharingServicePicker(items: [body(kind, title: title, date: date)] + previews)
        let delegate = Subject(title)
        picker.delegate = delegate
        Subject.current = delegate  // the picker holds its delegate weakly
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    /// Sets the subject on the service the user picks (Mail).
    @MainActor private final class Subject: NSObject, @preconcurrency NSSharingServicePickerDelegate {
        static var current: Subject?
        let subject: String
        init(_ subject: String) { self.subject = subject }

        func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            service?.subject = subject
        }
    }
}

/// The App Store's review request (Apple's own sheet; macOS decides whether it shows, at most three
/// times a year): when a transcript opens in the window, from the third one, not in the first week,
/// once per app version, never while Band·je is busy. Only in the App Store build.
enum ReviewPrompt {
    static func shouldAsk(transcripts: Int, firstLaunch: Date?, now: Date, askedVersion: String?, version: String, busy: Bool) -> Bool {
        guard let firstLaunch, !busy, transcripts >= 3, askedVersion != version else { return false }
        return now.timeIntervalSince(firstLaunch) >= 7 * 86_400
    }

    static var firstLaunch: Date? { UserDefaults.standard.object(forKey: "firstLaunchDate") as? Date }

    /// Called at every launch: remembers the first one.
    static func noteLaunch() {
        if firstLaunch == nil { UserDefaults.standard.set(Date(), forKey: "firstLaunchDate") }
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
    static var askedVersion: String? { UserDefaults.standard.string(forKey: "reviewAskedVersion") }
    static func noteAsked() { UserDefaults.standard.set(version, forKey: "reviewAskedVersion") }
}
