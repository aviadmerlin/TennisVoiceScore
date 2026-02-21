import SwiftUI
import Speech
import AVFoundation
import Combine

// MARK: - Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case hebrew = "עברית"
    case english = "English"
    var id: String { rawValue }

    var recognizerLocale: Locale {
        switch self {
        case .hebrew: return Locale(identifier: "he-IL")
        case .english: return Locale(identifier: "en-US")
        }
    }
}

// MARK: - Tennis Model

enum Point: Int, CaseIterable { case love = 0, fifteen, thirty, forty, adv }

func pointLabelUI(_ p: Point) -> String {
    switch p {
    case .love: return "0"
    case .fifteen: return "15"
    case .thirty: return "30"
    case .forty: return "40"
    case .adv: return "AD"
    }
}

func pointWordEN(_ p: Point) -> String {
    switch p {
    case .love: return "love"
    case .fifteen: return "fifteen"
    case .thirty: return "thirty"
    case .forty: return "forty"
    case .adv: return "advantage"
    }
}

func pointWordHE(_ p: Point) -> String {
    switch p {
    case .love: return "אפס"
    case .fifteen: return "חמש עשרה"
    case .thirty: return "שלושים"
    case .forty: return "ארבעים"
    case .adv: return "יתרון"
    }
}

struct MatchState: Equatable {
    var aPoint: Point = .love
    var bPoint: Point = .love
    var aGames: Int = 0
    var bGames: Int = 0
}

func isDeuce(_ s: MatchState) -> Bool { s.aPoint == .forty && s.bPoint == .forty }

func nextPoint(_ p: Point) -> Point {
    switch p {
    case .love: return .fifteen
    case .fifteen: return .thirty
    case .thirty: return .forty
    case .forty: return .adv
    case .adv: return .adv
    }
}

func resetPoints(_ s: MatchState) -> MatchState {
    var x = s
    x.aPoint = .love
    x.bPoint = .love
    return x
}

func winGameA(_ s: MatchState) -> MatchState {
    var x = resetPoints(s)
    x.aGames += 1
    return x
}

func winGameB(_ s: MatchState) -> MatchState {
    var x = resetPoints(s)
    x.bGames += 1
    return x
}

func pointToA(_ s: MatchState) -> MatchState {
    if s.aPoint == .adv { return winGameA(s) }

    if s.bPoint == .adv {
        var x = s
        x.aPoint = .forty
        x.bPoint = .forty
        return x
    }

    if isDeuce(s) {
        var x = s
        x.aPoint = .adv
        return x
    }

    if s.aPoint == .forty && s.bPoint != .forty { return winGameA(s) }

    var x = s
    x.aPoint = nextPoint(s.aPoint)
    return x
}

func pointToB(_ s: MatchState) -> MatchState {
    if s.bPoint == .adv { return winGameB(s) }

    if s.aPoint == .adv {
        var x = s
        x.aPoint = .forty
        x.bPoint = .forty
        return x
    }

    if isDeuce(s) {
        var x = s
        x.bPoint = .adv
        return x
    }

    if s.bPoint == .forty && s.aPoint != .forty { return winGameB(s) }

    var x = s
    x.bPoint = nextPoint(s.bPoint)
    return x
}

// MARK: - Commands

enum Command: Equatable { case pointA, pointB, undo, score, none }

/// Debug info for speech recognition (optional overlay).
struct SpeechDebugInfo: Equatable {
    let rawTranscript: String
    let normalizedTranscript: String
    let detectedCommand: Command
    let reason: String
    let timestamp: Date
}

/// Normalizes for matching: letters + digits + single spaces, collapsed and trimmed. Case-insensitive for Latin.
func normalizedForCommand(_ s: String) -> String {
    let lowered = s.lowercased()
    var result: [Character] = []
    var lastWasSpace = false
    for char in lowered {
        let scalar = char.unicodeScalars.first!
        if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
            result.append(char)
            lastWasSpace = false
        } else if CharacterSet.whitespacesAndNewlines.contains(scalar), !lastWasSpace {
            result.append(" ")
            lastWasSpace = true
        }
    }
    let str = String(result).trimmingCharacters(in: .whitespacesAndNewlines)
    return str.replacingOccurrences(of: "  ", with: " ", options: .regularExpression)
}

/// Returns true if normalized string `t` contains `word` as a whole word (with spaces or boundaries).
func normalizedContainsWord(_ t: String, word: String) -> Bool {
    guard !word.isEmpty else { return false }
    let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
    if w.isEmpty { return false }
    return t == w || t.hasPrefix(w + " ") || t.hasSuffix(" " + w) || t.contains(" " + w + " ")
}

func parseCommandHebrew(_ text: String, playerA: String, playerB: String) -> Command {
    let raw = text.lowercased()
    let t = normalizedForCommand(text)
    let a = normalizedForCommand(playerA)
    let b = normalizedForCommand(playerB)

    // Undo: synonyms
    if t.contains("בטל") || t.contains("חזור") || t.contains("אחורה") { return .undo }
    // Score: synonyms
    if t.contains("תוצאה") || t.contains("תן תוצאה") { return .score }

    // Point A/B by number: whole-word only to avoid false positives
    if normalizedContainsWord(t, word: "אחד") { return .pointA }
    if normalizedContainsWord(t, word: "שתיים") || normalizedContainsWord(t, word: "שתים") { return .pointB }

    let hasPoint = raw.contains("נקודה") || raw.contains("תן") || raw.contains("תני") || raw.contains("תנו")
    let hasTo = raw.contains("ל")

    if hasPoint && hasTo {
        if a.count >= 2, t.contains(a) { return .pointA }
        if b.count >= 2, t.contains(b) { return .pointB }
        return .none
    }

    // Direct name match: require minimum length and word-boundary to avoid common words
    if a.count >= 2, normalizedContainsWord(t, word: a) { return .pointA }
    if b.count >= 2, normalizedContainsWord(t, word: b) { return .pointB }

    return .none
}

func parseCommandEnglish(_ text: String, playerA: String, playerB: String) -> Command {
    let raw = text.lowercased()
    let t = normalizedForCommand(text)
    let a = normalizedForCommand(playerA)
    let b = normalizedForCommand(playerB)

    if t.contains("undo") { return .undo }
    if t.contains("score") { return .score }

    if normalizedContainsWord(t, word: "one") { return .pointA }
    if normalizedContainsWord(t, word: "two") { return .pointB }

    let hasPoint = raw.contains("point") || raw.contains("give")
    let hasTo = raw.contains("to")

    if hasPoint && hasTo {
        if a.count >= 2, t.contains(a) { return .pointA }
        if b.count >= 2, t.contains(b) { return .pointB }
        return .none
    }

    if a.count >= 2, normalizedContainsWord(t, word: a) { return .pointA }
    if b.count >= 2, normalizedContainsWord(t, word: b) { return .pointB }

    return .none
}

func parseCommandByLanguage(_ text: String, playerA: String, playerB: String, lang: AppLanguage) -> Command {
    switch lang {
    case .hebrew: return parseCommandHebrew(text, playerA: playerA, playerB: playerB)
    case .english: return parseCommandEnglish(text, playerA: playerA, playerB: playerB)
    }
}

// MARK: - Command parsing debug / verification

/// Call from debug or tests: run sample transcripts and return (transcript, normalized, command, note).
func debugParseSamples(lang: AppLanguage, playerA: String = "אביעד", playerB: String = "ניב") -> [(String, String, Command, String)] {
    let samples: [(String, AppLanguage)] = lang == .hebrew
        ? [
            ("אחד", .hebrew),
            ("  אחד  ", .hebrew),
            ("שתיים", .hebrew),
            ("שתים", .hebrew),
            ("בטל", .hebrew),
            ("חזור", .hebrew),
            ("תוצאה", .hebrew),
            ("תן תוצאה", .hebrew),
            ("נקודה לאביעד", .hebrew),
            ("נקודה לניב", .hebrew),
            ("אה אחד", .hebrew),
            ("אח", .hebrew),
        ]
        : [
            ("one", .english),
            ("two", .english),
            ("undo", .english),
            ("score", .english),
            ("point to john", .english),
        ]
    return samples.map { text, l in
        let n = normalizedForCommand(text)
        let cmd = parseCommandByLanguage(text, playerA: playerA, playerB: playerB, lang: l)
        let note = cmd == .none ? "no match" : "ok"
        return (text, n, cmd, note)
    }
}

// MARK: - AI TTS Player (Cloudflare Worker -> Azure -> MP3)

@MainActor
final class AITTSPlayer: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var onFinish: (() -> Void)?

    func speak(endpoint: URL, text: String, onFinish: (() -> Void)? = nil) async throws {
        self.onFinish = onFinish

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .allowBluetoothA2DP, .allowAirPlay]
        )
        try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

        let p = try AVAudioPlayer(data: data)
        p.delegate = self
        p.prepareToPlay()
        p.play()
        player = p
    }

    func stop() {
        player?.stop()
        player = nil
        onFinish = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish?()
        onFinish = nil
    }
}

// MARK: - Voice Manager

@MainActor
final class VoiceManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "he-IL"))

    private let synthesizer = AVSpeechSynthesizer()

    private let aiTTS = AITTSPlayer()
    private let aiEndpoint = URL(string: "https://tennis-tts.aviadmerlin.workers.dev/")!

    @Published var appLanguage: AppLanguage = .hebrew

    @Published var isListening: Bool = false
    @Published var lastHeard: String = ""
    @Published var status: String = "מוכן"

    @Published var playerAName: String = "אביעד"
    @Published var playerBName: String = "ניב"

    @Published var state: MatchState = .init()

    @Published var canUndo: Bool = false

    private var history: [MatchState] = []

    private var didHandleThisUtterance: Bool = false
    private var resumeListeningAfterSpeak: Bool = false

    /// Debounce: require same command twice in a row (or final) before firing.
    private var lastPartialCommand: Command = .none
    private var lastPartialCommandCount: Int = 0

    /// Cooldown (ms) after applying a command to avoid double triggers.
    private static let commandCooldownMs: Int = 750
    private var lastCommandAppliedTime: Date = .distantPast

    /// Debug: optional overlay (off by default).
    @Published var showSpeechDebug: Bool = false
    @Published var speechDebugInfo: SpeechDebugInfo?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func requestPermissions() async {
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioSession.sharedInstance().requestRecordPermission { ok in cont.resume(returning: ok) }
        }
        _ = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { s in cont.resume(returning: s) }
        }
    }

    private func rebuildRecognizer() {
        recognizer = SFSpeechRecognizer(locale: appLanguage.recognizerLocale)
    }

    private func safeA() -> String {
        let x = playerAName.trimmingCharacters(in: .whitespacesAndNewlines)
        return x.isEmpty ? (appLanguage == .hebrew ? "שחקן 1" : "Player 1") : x
    }

    private func safeB() -> String {
        let x = playerBName.trimmingCharacters(in: .whitespacesAndNewlines)
        return x.isEmpty ? (appLanguage == .hebrew ? "שחקן 2" : "Player 2") : x
    }

    // MARK: Audio Session

    /// Prefer Bluetooth HFP for voice when available; otherwise built-in mic is used (no forced override).
    private func setPreferredInputForVoiceIfNeeded(_ session: AVAudioSession) {
        guard let inputs = session.availableInputs else { return }
        if let bt = inputs.first(where: { $0.portType == .bluetoothHFP }) {
            try? session.setPreferredInput(bt)
        }
        // Else: leave default (built-in mic), which is better when phone is not close to mouth.
    }

    /// Configure session for voice recognition: voice-optimized mode, then activate before starting engine.
    private func configureForListening() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            setPreferredInputForVoiceIfNeeded(session)
        } catch { }
    }

    private func configureForSpeaking() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback,
                                    mode: .spokenAudio,
                                    options: [.duckOthers, .allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { }
    }

    // MARK: Speaking (AI first, system fallback)

    func speak(_ text: String) {
        resumeListeningAfterSpeak = isListening
        if isListening { stop() }

        Task { @MainActor in
            do {
                try await aiTTS.speak(endpoint: aiEndpoint, text: text) {
                    if self.resumeListeningAfterSpeak {
                        self.resumeListeningAfterSpeak = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            try? self.start()
                        }
                    }
                }
            } catch {
                self.speakSystemFallback(text)
            }
        }
    }

    private func speakSystemFallback(_ text: String) {
        resumeListeningAfterSpeak = isListening
        if isListening { stop() }

        configureForSpeaking()

        synthesizer.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: appLanguage == .hebrew ? "he-IL" : "en-US")
        u.rate = 0.48
        u.pitchMultiplier = 1.0
        u.volume = 1.0
        synthesizer.speak(u)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if resumeListeningAfterSpeak {
            resumeListeningAfterSpeak = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                try? self.start()
            }
        }
    }

    // MARK: Speak formatting
    // ✅ Point updates: points only
    // ✅ When someone wins a game: announce game winner + games score

    private func pointsOnlyText() -> String {
        let a = safeA()
        let b = safeB()

        switch appLanguage {
        case .english:
            if isDeuce(state) { return "Deuce." }
            if state.aPoint == .adv { return "Advantage \(a)." }
            if state.bPoint == .adv { return "Advantage \(b)." }
            return "\(a) \(pointWordEN(state.aPoint)), \(b) \(pointWordEN(state.bPoint))."
        case .hebrew:
            if isDeuce(state) { return "דוס." }
            if state.aPoint == .adv { return "יתרון \(a)." }
            if state.bPoint == .adv { return "יתרון \(b)." }
            return "\(a) \(pointWordHE(state.aPoint)), \(b) \(pointWordHE(state.bPoint))."
        }
    }

    private func gameWinText(winnerIsA: Bool) -> String {
        let a = safeA()
        let b = safeB()

        switch appLanguage {
        case .english:
            let winner = winnerIsA ? a : b
            return "Game \(winner). Games: \(a) \(state.aGames), \(b) \(state.bGames)."
        case .hebrew:
            let winner = winnerIsA ? a : b
            return "משחקון ל-\(winner). משחקונים: \(a) \(state.aGames), \(b) \(state.bGames)."
        }
    }

    private func fullScoreToSpeak() -> String {
        // For the "Speak score" button: always include games
        let a = safeA()
        let b = safeB()

        switch appLanguage {
        case .english:
            if isDeuce(state) {
                return "Deuce. Games: \(a) \(state.aGames), \(b) \(state.bGames)."
            }
            if state.aPoint == .adv {
                return "Advantage \(a). Games: \(a) \(state.aGames), \(b) \(state.bGames)."
            }
            if state.bPoint == .adv {
                return "Advantage \(b). Games: \(a) \(state.aGames), \(b) \(state.bGames)."
            }
            return "\(a) \(pointWordEN(state.aPoint)), \(b) \(pointWordEN(state.bPoint)). Games: \(a) \(state.aGames), \(b) \(state.bGames)."

        case .hebrew:
            if isDeuce(state) {
                return "דוס. משחקונים: \(a) \(state.aGames), \(b) \(state.bGames)."
            }
            if state.aPoint == .adv {
                return "יתרון \(a). משחקונים: \(a) \(state.aGames), \(b) \(state.bGames)."
            }
            if state.bPoint == .adv {
                return "יתרון \(b). משחקונים: \(a) \(state.aGames), \(b) \(state.bGames)."
            }
            return "\(a) \(pointWordHE(state.aPoint)), \(b) \(pointWordHE(state.bPoint)). משחקונים: \(a) \(state.aGames), \(b) \(state.bGames)."
        }
    }

    func speakScore() { speak(fullScoreToSpeak()) }

    // MARK: Game

    private func pushHistory() {
        history.append(state)
        canUndo = !history.isEmpty
    }

    func undo() {
        guard let prev = history.popLast() else { return }
        state = prev
        canUndo = !history.isEmpty
        status = (appLanguage == .hebrew) ? "בוטל" : "Undone"
        speak(fullScoreToSpeak())
    }

    func resetMatch() {
        history.removeAll()
        canUndo = false
        state = .init()
        status = (appLanguage == .hebrew) ? "משחק חדש" : "New match"
        speak((appLanguage == .hebrew ? "משחק חדש. " : "New match. ") + fullScoreToSpeak())
    }

    private func apply(_ cmd: Command) {
        switch cmd {
        case .pointA:
            let prev = state
            pushHistory()
            state = pointToA(state)
            status = (appLanguage == .hebrew) ? "נקודה ל-\(safeA())" : "Point to \(safeA())"
            let gameWon = (state.aGames != prev.aGames)
            speak(gameWon ? gameWinText(winnerIsA: true) : pointsOnlyText())

        case .pointB:
            let prev = state
            pushHistory()
            state = pointToB(state)
            status = (appLanguage == .hebrew) ? "נקודה ל-\(safeB())" : "Point to \(safeB())"
            let gameWon = (state.bGames != prev.bGames)
            speak(gameWon ? gameWinText(winnerIsA: false) : pointsOnlyText())

        case .undo:
            undo()
        case .score:
            speakScore()
        case .none:
            status = (appLanguage == .hebrew) ? "לא זיהיתי" : "Not recognized"
        }
    }

    // MARK: Start/Stop

    func start() throws {
        guard !isListening else { return }

        aiTTS.stop()

        rebuildRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            status = (appLanguage == .hebrew) ? "זיהוי לא זמין" : "Recognition unavailable"
            return
        }

        configureForListening()

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(iOS 16.0, *) { request.addsPunctuation = false }

        switch appLanguage {
        case .hebrew:
            request.contextualStrings = [
                safeA(), safeB(),
                "נקודה", "תן", "תני", "תנו", "ל", "אחד", "שתיים", "שתים",
                "בטל", "חזור", "אחורה", "תוצאה", "תן תוצאה",
            ]
        case .english:
            request.contextualStrings = [safeA(), safeB(), "point", "give", "to", "one", "two", "undo", "score"]
        }

        didHandleThisUtterance = false
        lastPartialCommand = .none
        lastPartialCommandCount = 0

        let input = audioEngine.inputNode
        let format = input.inputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            self.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        isListening = true
        status = appLanguage == .hebrew ? "מקשיב..." : "Listening..."

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let heard = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.lastHeard = heard
                    let cmd = parseCommandByLanguage(heard,
                                                     playerA: self.playerAName,
                                                     playerB: self.playerBName,
                                                     lang: self.appLanguage)

                    let cooldownPassed = Date().timeIntervalSince(self.lastCommandAppliedTime) * 1000 >= Double(Self.commandCooldownMs)
                    let canFire = !self.didHandleThisUtterance && cooldownPassed

                    if result.isFinal {
                        if cmd != .none, canFire {
                            self.fireCommand(cmd)
                        } else {
                            self.lastPartialCommand = .none
                            self.lastPartialCommandCount = 0
                            self.stop()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { try? self.start() }
                        }
                    } else {
                        if cmd == self.lastPartialCommand {
                            self.lastPartialCommandCount += 1
                        } else {
                            self.lastPartialCommand = cmd
                            self.lastPartialCommandCount = 1
                        }
                        let stablePartial = cmd != .none && self.lastPartialCommandCount >= 2 && canFire
                        if stablePartial {
                            self.fireCommand(cmd)
                        }
                    }

                    if self.showSpeechDebug {
                        let reason: String
                        if result.isFinal {
                            reason = cmd != .none && canFire ? "final+cooldown ok" : (cmd == .none ? "final, no command" : "final, cooldown/dup")
                        } else {
                            reason = self.lastPartialCommandCount >= 2 && cmd != .none ? "2x partial" : "partial"
                        }
                        self.speechDebugInfo = SpeechDebugInfo(
                            rawTranscript: heard,
                            normalizedTranscript: normalizedForCommand(heard),
                            detectedCommand: cmd,
                            reason: reason,
                            timestamp: Date()
                        )
                    }
                }
            }

            if error != nil {
                Task { @MainActor in
                    self.status = self.appLanguage == .hebrew ? "שגיאה" : "Error"
                    self.stop()
                }
            }
        }
    }

    private func fireCommand(_ cmd: Command) {
        didHandleThisUtterance = true
        lastCommandAppliedTime = Date()
        lastPartialCommand = .none
        lastPartialCommandCount = 0
        apply(cmd)
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { try? self.start() }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
    }
}

// MARK: - UI (Figma Premium)

struct ContentView: View {
    @StateObject private var vm = VoiceManager()

    private var bgTop: Color { Color(red: 0.06, green: 0.08, blue: 0.12) }
    private var bgBottom: Color { Color(red: 0.03, green: 0.05, blue: 0.09) }

    private var accentGreen: Color { Color(red: 0.20, green: 1.00, blue: 0.35) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                languagePicker

                playersRow

                serverDot

                scoreCard

                statusPill

                micButton

                bottomButtons

                speakButton

                Spacer(minLength: 10)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            if vm.showSpeechDebug, let info = vm.speechDebugInfo {
                speechDebugOverlay(info: info)
            }
        }
        .onAppear { Task { await vm.requestPermissions() } }
    }

    private func speechDebugOverlay(info: SpeechDebugInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Speech debug")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
            Text("Raw: \(info.rawTranscript)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
            Text("Norm: \(info.normalizedTranscript)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
            Text("Cmd: \(String(describing: info.detectedCommand))")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
            Text("Reason: \(info.reason)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var languagePicker: some View {
        Picker("Language", selection: $vm.appLanguage) {
            ForEach(AppLanguage.allCases) { lang in
                Text(lang.rawValue).tag(lang)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: vm.appLanguage) { _ in
            if vm.isListening {
                vm.stop()
                try? vm.start()
            }
        }
    }

    private var playersRow: some View {
        HStack(spacing: 14) {
            playerCard(title: vm.appLanguage == .hebrew ? "שחקן 1" : "Player 1", text: $vm.playerAName)
            playerCard(title: vm.appLanguage == .hebrew ? "שחקן 2" : "Player 2", text: $vm.playerBName)
        }
    }

    private func playerCard(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text(vm.appLanguage == .hebrew ? "סטים: 0 | משחקונים: 0" : "Sets: 0 | Games: 0")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))

            TextField(vm.appLanguage == .hebrew ? "שם..." : "Name...", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        }
        .padding(16)
        .premiumCard()
    }

    private var serverDot: some View {
        Circle()
            .fill(accentGreen)
            .frame(width: 16, height: 16)
            .shadow(color: accentGreen.opacity(0.7), radius: 14, x: 0, y: 0)
            .padding(.top, -6)
    }

    private var scoreCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Text(pointLabelUI(vm.state.aPoint))
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text(":")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 10)

                Text(pointLabelUI(vm.state.bPoint))
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(vm.appLanguage == .hebrew
                 ? "משחקונים: \(vm.state.aGames) : \(vm.state.bGames)"
                 : "Games: \(vm.state.aGames) : \(vm.state.bGames)")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.70))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .premiumCard(cornerRadius: 28)
    }

    private var statusPill: some View {
        HStack(spacing: 10) {
            Text(vm.appLanguage == .hebrew ? "סטטוס:" : "Status:")
                .foregroundStyle(.white.opacity(0.60))
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Text(vm.status)
                .foregroundStyle(.white.opacity(0.92))
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .premiumCard(cornerRadius: 22)
        .overlay(alignment: .trailing) {
            if !vm.lastHeard.isEmpty {
                Text(vm.lastHeard)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white.opacity(0.45))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(.trailing, 14)
            }
        }
        .onLongPressGesture(minimumDuration: 0.8) {
            vm.showSpeechDebug.toggle()
        }
    }

    private var micButton: some View {
        Button {
            if vm.isListening { vm.stop() } else { try? vm.start() }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 92, height: 92)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
        }
        .buttonStyle(.plain)
        .overlay {
            Circle()
                .stroke(vm.isListening ? accentGreen.opacity(0.9) : Color.clear, lineWidth: 3)
                .frame(width: 102, height: 102)
                .shadow(color: vm.isListening ? accentGreen.opacity(0.6) : .clear, radius: 18)
                .animation(.easeInOut(duration: 0.25), value: vm.isListening)
        }
        .padding(.top, 2)
    }

    private var bottomButtons: some View {
        HStack(spacing: 14) {
            Button {
                vm.undo()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.uturn.backward")
                    Text(vm.appLanguage == .hebrew ? "בטל" : "Undo")
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(vm.canUndo ? 0.80 : 0.35))
            .premiumCardButton(isEnabled: vm.canUndo)
            .disabled(!vm.canUndo)

            Button {
                vm.resetMatch()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                    Text(vm.appLanguage == .hebrew ? "חדש" : "New")
                }
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.90))
            .premiumCardButton(isEnabled: true)
        }
        .padding(.top, 6)
    }

    private var speakButton: some View {
        Button {
            vm.speakScore()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill")
                Text(vm.appLanguage == .hebrew ? "הקרא תוצאה" : "Speak score")
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.80))
        .premiumCardButton(isEnabled: true, cornerRadius: 18)
        .padding(.top, 2)
    }
}

// MARK: - Styling Helpers

private extension View {
    func premiumCard(cornerRadius: CGFloat = 24) -> some View {
        self
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 16)
    }

    func premiumCardButton(isEnabled: Bool, cornerRadius: CGFloat = 22) -> some View {
        self
            .background(Color.white.opacity(isEnabled ? 0.06 : 0.03))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.12 : 0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isEnabled ? 0.30 : 0.18), radius: 20, x: 0, y: 14)
    }
}

#Preview { ContentView() }
