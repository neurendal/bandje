import Foundation

// Ported from the iPhone app (bandje-ios Bandje/Transcription.swift); keep the two in step.

// MARK: - Display: turns and sentences (click to seek, follow playback)

struct TranscriptSentence: Equatable, Sendable {
    var start: Double
    var end: Double
    var text: String
}

struct TranscriptTurn: Identifiable, Equatable, Sendable {
    var id: Int
    /// Original label ("" without speakers).
    var speaker: String
    var start: Double
    var sentences: [TranscriptSentence]
    /// A later paragraph of the same speaker's turn (no name shown).
    var continued = false
}

enum TranscriptLayout {
    /// A paragraph ends at the first sentence end after this many seconds (long monologues,
    /// transcripts without speakers).
    static let paragraphSeconds = 60.0

    /// Turns (consecutive segments of one speaker) cut into sentences (after `.`, `?`, `!`, `…`,
    /// or at a pause longer than `TranscriptWriter.pause`), and into paragraphs of about
    /// `paragraphSeconds`.
    static func turns(_ t: Transcript) -> [TranscriptTurn] {
        var out: [TranscriptTurn] = []
        for turn in sentenceTurns(t) {
            var paragraph: [TranscriptSentence] = []
            for sentence in turn.sentences {
                paragraph.append(sentence)
                if sentence.end - paragraph[0].start >= paragraphSeconds {
                    out.append(TranscriptTurn(id: out.count, speaker: turn.speaker, start: paragraph[0].start,
                                              sentences: paragraph, continued: paragraph[0].start > turn.start))
                    paragraph = []
                }
            }
            if !paragraph.isEmpty {
                out.append(TranscriptTurn(id: out.count, speaker: turn.speaker, start: paragraph[0].start,
                                          sentences: paragraph, continued: paragraph[0].start > turn.start))
            }
        }
        return out
    }

    private static func sentenceTurns(_ t: Transcript) -> [TranscriptTurn] {
        TranscriptWriter.joinConsecutive(t.segments).enumerated().map { index, seg in
            var sentences: [TranscriptSentence] = []
            var current: [TimedWord] = []
            func flush() {
                guard let first = current.first else { return }
                sentences.append(TranscriptSentence(start: first.start, end: current.map(\.end).max() ?? first.end,
                                                    text: current.map(\.text).joined(separator: " ")))
                current = []
            }
            for (i, word) in seg.words.enumerated() {
                current.append(word)
                let next = i + 1 < seg.words.count ? seg.words[i + 1] : nil
                let ends = word.text.hasSuffix(".") || word.text.hasSuffix("?") || word.text.hasSuffix("!") || word.text.hasSuffix("…")
                if ends || next.map({ $0.start - word.end > TranscriptWriter.pause }) == true { flush() }
            }
            flush()
            return TranscriptTurn(id: index, speaker: seg.speaker, start: seg.start, sentences: sentences)
        }
    }

    /// The sentence playing at `time`: the last one that started at or before it (turn, sentence).
    static func active(at time: Double, in turns: [TranscriptTurn]) -> (turn: Int, sentence: Int)? {
        var found: (Int, Int)?
        for turn in turns {
            guard turn.start <= time + 0.05 else { break }
            for (i, s) in turn.sentences.enumerated() where s.start <= time + 0.05 { found = (turn.id, i) }
        }
        return found
    }
}

/// A summary's text as blocks for the window: headings, bullets, paragraphs.
enum SummaryBlock: Equatable {
    case heading(String)
    case bullet(String)
    case paragraph(String)

    static func parse(_ body: String) -> [SummaryBlock] {
        body.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("#") { return .heading(line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)) }
            for bullet in ["- ", "* ", "• "] where line.hasPrefix(bullet) {
                return .bullet(line.dropFirst(bullet.count).trimmingCharacters(in: .whitespaces))
            }
            return .paragraph(line)
        }
    }
}
