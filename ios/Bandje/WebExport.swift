// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import Foundation
import SwiftUI

/// "Share as web page": one self-contained `.html` for a recording, to send to anyone. The player,
/// the transcript (click a turn to listen), the summaries as tabs, the audio embedded; Band·je's
/// logo and a link to band.je. Static: every text is escaped, no external resources, and no way
/// back into the app. Copied from the Mac app (bandje/Sources/Bandje/WebExport.swift, commit
/// 417d5e2) with the iPhone's helpers; keep the two in step.
enum WebExport {
    struct Summary: Equatable {
        var name: String
        var markdown: String
    }

    /// The only URL in our code besides the About links (CLAUDE.md limit 1).
    static let siteURL = "https://band.je"

    /// Summaries in the recording's folder: the iPhone's `<title> <word>.md` and the Mac's
    /// `<title> <word> <template>.md`, sorted by name.
    static func summaries(in folder: URL) -> [Summary] {
        let base = folder.lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { url -> Summary? in
            let name = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "md", name.hasPrefix(base + " "),
                  let md = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let rest = name.dropFirst(base.count + 1)
            let template = rest.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init)
                ?? String(localized: "Summary")
            return Summary(name: template, markdown: Summaries.body(ofDocument: md))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Writes the page for `recording` to a temporary file named after it, for the share sheet. The
    /// audio goes in as mono speech at 32 kbit/s (about 14 MB per hour).
    static func export(_ recording: Recording, transcript: Transcript) async throws -> URL {
        var audio: (base64: String, type: String)?
        if let file = recording.audio {
            audio = (try await compactAudio(file).base64EncodedString(), "audio/mp4")
        }
        let logo = await logoPNG()?.base64EncodedString()
        let html = page(transcript, summaries: summaries(in: recording.folder), audio: audio, logoBase64: logo)
        let dir = FileManager.default.temporaryDirectory.appending(path: "Share/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: Storage.safeName(recording.title) + ".html")
        try Data(html.utf8).write(to: url, options: .atomic)
        return url
    }

    /// The cassette, small, as the page's logo.
    @MainActor static func logoPNG() -> Data? {
        let renderer = ImageRenderer(content: CassetteView(state: CassetteState()).frame(width: 64)
            .environment(\.colorScheme, .light))
        renderer.scale = 2
        return renderer.uiImage?.pngData()
    }

    /// The recording as AAC mono 22.05 kHz at 32 kbit/s: speech stays clear, an hour is ~14 MB.
    /// Written with ExtAudioFile: AVAudioFile ignores the bitrate (it gives ~58 kbit/s).
    static func compactAudio(_ source: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let input = try AVAudioFile(forReading: source)
            let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22_050, channels: 1, interleaved: false)!
            guard let converter = AVAudioConverter(from: input.processingFormat, to: mono) else { throw CocoaError(.fileWriteUnknown) }
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
                     select: String? = nil) -> String {
        let title = t.title
        let labels = t.speakerLabels
        var tabs: [(id: String, name: String, body: String)] = []
        for (i, s) in summaries.enumerated() {
            tabs.append(("s\(i)", s.name, "<article class=\"summary\">\n" + markdown(s.markdown) + "</article>"))
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
        if joined.isEmpty { turns = "<p class=\"muted\">\(escape(String(localized: "No speech recognised.")))</p>" }
        tabs.append(("transcript", String(localized: "Transcript"), "<section class=\"turns\">\n" + turns + "</section>"))

        let active = select.flatMap { name in summaries.firstIndex { $0.name == name }.map { "s\($0)" } }
            ?? (summaries.isEmpty ? "transcript" : tabs[0].id)
        let tabButtons = tabs.map { "<button role=\"tab\" data-tab=\"\($0.id)\"\($0.id == active ? " aria-selected=\"true\"" : "")>\(escape($0.name))</button>" }.joined()
        let panels = tabs.map { "<div role=\"tabpanel\" id=\"\($0.id)\"\($0.id == active ? "" : " hidden")>\n\($0.body)\n</div>" }.joined(separator: "\n")
        let logo = logoBase64.map { "<img class=\"logo\" alt=\"Band·je\" src=\"data:image/png;base64,\($0)\">" } ?? ""
        // The logo as the page's icon too (browser tab, home screen), and big in the footer.
        let icons = logoBase64.map { "<link rel=\"icon\" type=\"image/png\" href=\"data:image/png;base64,\($0)\">\n<link rel=\"apple-touch-icon\" href=\"data:image/png;base64,\($0)\">" } ?? ""
        let footerLogo = logoBase64.map { "<img class=\"logo big\" alt=\"\" src=\"data:image/png;base64,\($0)\">" } ?? ""
        let player = audio.map { "<audio id=\"audio\" controls preload=\"metadata\" src=\"data:\($0.type);base64,\($0.base64)\"></audio>" } ?? ""
        let lang = Summaries.appLanguage
        let facts = TranscriptWriter.headerLines(t).first.map { String($0.dropFirst(2)) } ?? ""

        return """
        <!doctype html>
        <html lang="\(lang)">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(escape(title)) · Band·je</title>
        \(icons)
        <style>\(css)</style>
        </head>
        <body>
        <header>
        <div class="wrap">
        <div class="brand">\(logo)<span>Band·je</span></div>
        <h1>\(escape(title))</h1>
        <p class="muted">\(escape(facts))</p>
        \(player)
        <noscript><p class="muted">\(escape(String(localized: "Open this page in Safari to listen and to follow the transcript.")))</p></noscript>
        <nav role="tablist">\(tabButtons)</nav>
        </div>
        </header>
        <main>
        \(panels)
        </main>
        <footer>
        <div class="wrap">
        \(footerLogo)
        <p><strong>\(escape(String(localized: "Band·je records your conversations and turns them into text.")))</strong><br>
        \(escape(String(localized: "Everything on your own device: no tokens, super fast, with who said what, in 25 languages.")))</p>
        <p><a href="\(siteURL)">band.je</a></p>
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
    .logo{width:28px;height:28px;border-radius:7px;object-fit:contain}
    .logo.big{width:40px;height:40px;display:block;margin-bottom:8px}
    h1{font-size:20px;margin:0;line-height:1.3}
    .muted{color:var(--muted);margin:2px 0 0;font-size:14px}
    .brand{display:flex;gap:8px;align-items:center;font-weight:700;color:var(--accent);margin-bottom:8px}
    footer{padding:18px 16px 40px;border-top:1px solid var(--line);color:var(--muted);font-size:14px}
    footer strong{color:var(--fg)}footer p{margin:4px 0}
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
