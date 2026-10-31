import Foundation
import SwiftData

/// Daily mental training. Each practice is chosen for its evidence base and its
/// realistic dose, and is honest about its limits in `evidence`.
enum MindPractice: String, CaseIterable, Identifiable, Codable {
    case breath, stillness, focus, reframe, activation, gratitude, recall, unload, rest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breath: return "Resonance Breathing"
        case .stillness: return "Stillness"
        case .focus: return "Instant Dungeon: Focus"
        case .reframe: return "Thought Record"
        case .activation: return "One Valued Action"
        case .gratitude: return "Three Good Things"
        case .recall: return "Retrieval"
        case .unload: return "Unload"
        case .rest: return "Rest Without Sleep"
        }
    }

    var symbol: String {
        switch self {
        case .breath: return "wind"
        case .stillness: return "circle.dotted"
        case .focus: return "door.left.hand.open"
        case .reframe: return "arrow.triangle.2.circlepath"
        case .activation: return "figure.walk.motion"
        case .gratitude: return "sun.max"
        case .recall: return "brain"
        case .unload: return "pencil.and.scribble"
        case .rest: return "moon.zzz"
        }
    }

    var stat: Stat {
        switch self {
        case .focus, .recall: return .INT
        case .stillness, .rest: return .PER
        default: return .WIL
        }
    }

    var detail: String {
        switch self {
        case .breath: return "Five minutes at six breaths a minute: five seconds in, five seconds out, through the nose. Follow the circle."
        case .stillness: return "Sit upright. Rest attention on the breath. When the mind wanders, notice it and come back. The coming back is the rep."
        case .focus: return "Name one task. Phone in another room, one tab, one window. Enter for 25 or 50 minutes. On exit, write where to resume."
        case .reframe: return "Take one moment that stung. Write the thought it brought, the evidence for and against it, and a more balanced version. Rate the feeling before and after."
        case .activation: return "Do one small thing that matters to you or that you used to enjoy, today, even if you do not feel like it. Action first; motivation follows."
        case .gratitude: return "Write three things that went well and why they happened. Specific beats general."
        case .recall: return "Without looking, write three things you learned recently. Then check. Pulling it out is what makes it stay."
        case .unload: return "Write for 15 minutes about what is weighing on you. Do not edit. Nothing is kept unless you choose to keep it."
        case .rest: return "Lie down. Slow breath, then move attention through the body from feet to head. Not a replacement for sleep, a way to downshift."
        }
    }

    /// One line on what the research supports, without overselling.
    var evidence: String {
        switch self {
        case .breath: return "Slow breathing near six a minute raises heart-rate variability and reliably lowers felt stress. The best rate varies from person to person."
        case .stillness: return "Meditation programmes show moderate effects on anxiety and low mood. Ten minutes does about as much as thirty."
        case .focus: return "Switching tasks leaves attention residue. A written plan for where to resume reduces it."
        case .reframe: return "Reappraisal shifts emotion; it works as one tool among several, not a cure-all."
        case .activation: return "Behavioural activation is among the best-supported treatments for low mood, comparable to full CBT."
        case .gratitude: return "A small but consistent lift in wellbeing across many studies."
        case .recall: return "Retrieval and spacing are among the most robust findings in learning research."
        case .unload: return "Evidence is mixed; it may help most after a hard day. Use it when it helps."
        case .rest: return "Early, modest evidence for relaxation and sleep quality. It does not replace real sleep."
        }
    }

    /// Canon flavour, kept to things that are actually in the story.
    var canon: String {
        switch self {
        case .focus: return "An Instant Dungeon: a private gate where nothing else can reach you until it is cleared."
        case .reframe, .activation: return "Courage of the Weak was not about strength. It was choosing to act while afraid."
        case .recall: return "INT rises when knowledge is used, not when it is stored."
        case .stillness, .rest, .breath: return "Perception is trained in calm, not in noise."
        case .gratitude, .unload: return "Even the strongest hunter stayed human by remembering what he fought for."
        }
    }

    var minutes: Int {
        switch self {
        case .breath: return 5
        case .stillness: return 10
        case .focus: return 25
        case .rest: return 15
        case .unload: return 15
        default: return 0
        }
    }

    /// Written before the timer, e.g. the one task for a focus block.
    var before: [String] {
        switch self {
        case .focus: return ["The one task"]
        case .reframe: return ["What happened", "The thought it brought", "Evidence for it", "Evidence against it", "A more balanced thought"]
        case .activation: return ["What I did"]
        case .gratitude: return ["One", "Two", "Three"]
        case .recall: return ["One", "Two", "Three"]
        case .unload: return ["Write"]
        default: return []
        }
    }

    /// Written after the timer.
    var after: [String] { self == .focus ? ["Where to resume"] : [] }

    var ratesFeeling: Bool { self == .reframe || self == .activation }

    /// Expressive writing is for getting it out, not for keeping.
    var keepsTextByDefault: Bool { self != .unload }

    /// Which practice is offered on a given programme day.
    static func forDay(_ index: Int) -> MindPractice {
        let order: [MindPractice] = [.breath, .focus, .gratitude, .stillness, .reframe, .recall, .activation, .unload, .rest]
        return order[((index % order.count) + order.count) % order.count]
    }

    /// Offered when today's mood is low: gentle, short and doable.
    static let gentle: [MindPractice] = [.breath, .activation, .gratitude, .rest]
}

@Model
final class MindLog {
    var id: UUID
    var dayKey: String
    var practice: String
    var minutes: Int
    /// The written entries, one per field. Empty when the player chose not to keep them.
    var entries: [String]
    var feelingBefore: Int
    var feelingAfter: Int
    var date: Date

    init(dayKey: String, practice: MindPractice, minutes: Int, entries: [String], feelingBefore: Int = -1, feelingAfter: Int = -1) {
        self.id = UUID()
        self.dayKey = dayKey
        self.practice = practice.rawValue
        self.minutes = minutes
        self.entries = entries
        self.feelingBefore = feelingBefore
        self.feelingAfter = feelingAfter
        self.date = .now
    }
}

/// Canon passive skill. Here its level comes from the number of days with any
/// mental training, and like every skill it is never lost.
enum Tenacity {
    static let thresholds = [1, 5, 10, 20, 30, 50, 75, 100, 150, 200, 365]
    static func level(days: Int) -> Int { thresholds.filter { days >= $0 }.count }
    static func next(days: Int) -> Int? { thresholds.first { days < $0 } }
}

/// What the app gently says about mood patterns. Never a penalty, never XP.
enum SupportSignal: Equatable {
    case lowStretch(days: Int)
    case veryLowToday
    case elevatedShortSleep(days: Int)
}
