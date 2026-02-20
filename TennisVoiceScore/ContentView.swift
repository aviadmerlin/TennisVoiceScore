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

enum Command { case pointA, pointB, undo, score, none }

func normalizedForCommand(_ s: String) -> String {
    let lowered = s.lowercased()
    let filtered = lowered.unicodeScalars.filter { scalar in
        CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
    }
    return String(String.UnicodeScalarView(filtered))
}

func parseCommandHebrew(_ text: String, playerA: String, playerB: String) -> Command {
    let raw = text.lowercased()
    let t = normalizedForCommand(text)
    let a = normalizedForCommand(playerA)
    let b = normalizedForCommand(playerB)

    if t.contains("בטל") { return .undo }
    if t.contains("תוצאה") { return .score }

    if t == "אחד" { return .pointA }
    if t == "שתיים" || t == "שתים" { return .pointB }

    let hasPoint = raw.contains("נקודה") || raw.contains("תן") || raw.contains("תני") || raw.contains("תנו")
    let hasTo = raw.contains("ל")

    if hasPoint && hasTo {
        if !a.isEmpty && t.contains(a) { return .pointA }
        if !b.isEmpty && t.contains(b) { return .pointB }
        return .none
    }

    if !a.isEmpty && t.contains(a) { return .pointA }
    if !b.isEmpty && t.contains(b) { return .pointB }

    return .none
}

func parseCommandEnglish(_ text: String, playerA: String, playerB: String) -> Command {
    let raw = text.lowercased()
    let t = normalizedForCommand(text)
    let a = normalizedForCommand(playerA)
    let b = normalizedForCommand(playerB)

    if t.contains("undo") { return .undo }
    if t.contains("score") { return .score }

    if t == "one" { return .pointA }
    if t == "two" { return .pointB }

    let hasPoint = raw.contains("point") || raw.contains("give")
    let hasTo = raw.contains("to")

    if hasPoint && hasTo {
        if !a.isEmpty && t.contains(a) { return .pointA }
        if !b.isEmpty && t.contains(b) { return .pointB }
        return .none
    }

    if !a.isEmpty && t.contains(a) { return .pointA }
    if !b.isEmpty && t.contains(b) { return .pointB }

    return .none
}

func parseCommandByLanguage(_ text: String, playerA: String, playerB: String, lang: AppLanguage) -> Command {
    switch lang {
    case .hebrew: return parseCommandHebrew(text, playerA: playerA, playerB: playerB)
    case .english: return parseCommandEnglish(text, playerA: playerA, playerB: playerB)
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

    @Published var appLanguage: AppLanguage = .hebrew

    @Published var isListening: Bool = false
    @Published var lastHeard: String = ""
    @Published var status: String = "מוכן"

    @Published var playerAName: String = "אביעד"
    @Published var playerBName: String = "ניב"

    @Published var state: MatchState = .init()
    private var history: [MatchState] = []

    private var didHandleThisUtterance: Bool = false
    private var resumeListeningAfterSpeak: Bool = false

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

    private func preferBluetoothMicIfAvailable(_ session: AVAudioSession) {
        guard let inputs = session.availableInputs else { return }
        if let bt = inputs.first(where: { $0.portType == .bluetoothHFP }) {
            try? session.setPreferredInput(bt)
        }
    }

    private func configureForListening() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .videoRecording,
                                    options: [.allowBluetooth, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            preferBluetoothMicIfAvailable(session)
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

    // MARK: Speaking

    func speak(_ text: String) {
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

    private func scoreToSpeak() -> String {
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

    func speakScore() { speak(scoreToSpeak()) }

    // MARK: Game

    private func pushHistory() { history.append(state) }

    func undo() {
        guard let prev = history.popLast() else { return }
        state = prev
        status = (appLanguage == .hebrew) ? "בוטל" : "Undone"
        speakScore()
    }

    func resetMatch() {
        history.removeAll()
        state = .init()
        status = (appLanguage == .hebrew) ? "משחק חדש" : "New match"
        speak((appLanguage == .hebrew ? "משחק חדש. " : "New match. ") + scoreToSpeak())
    }

    private func apply(_ cmd: Command) {
        switch cmd {
        case .pointA:
            pushHistory()
            state = pointToA(state)
            status = (appLanguage == .hebrew) ? "נקודה ל-\(safeA())" : "Point to \(safeA())"
            speakScore()
        case .pointB:
            pushHistory()
            state = pointToB(state)
            status = (appLanguage == .hebrew) ? "נקודה ל-\(safeB())" : "Point to \(safeB())"
            speakScore()
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
            request.contextualStrings = [safeA(), safeB(), "נקודה", "תן", "ל", "אחד", "שתיים", "בטל", "תוצאה"]
        case .english:
            request.contextualStrings = [safeA(), safeB(), "point", "to", "one", "two", "undo", "score"]
        }

        didHandleThisUtterance = false

        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
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

                    if cmd != .none, self.didHandleThisUtterance == false {
                        self.didHandleThisUtterance = true
                        self.apply(cmd)
                        self.stop()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            try? self.start()
                        }
                    } else if result.isFinal {
                        self.stop()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            try? self.start()
                        }
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

// MARK: - UI (Professional Look)

struct ContentView: View {
    @StateObject private var vm = VoiceManager()

    private var startStopTitle: String {
        if vm.isListening { return vm.appLanguage == .hebrew ? "עצור" : "Stop" }
        return vm.appLanguage == .hebrew ? "התחל" : "Start"
    }

    private var startStopIcon: String { vm.isListening ? "stop.fill" : "mic.fill" }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.blue.opacity(0.65), Color.indigo],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .ignoresSafeArea()

            VStack(spacing: 18) {

                HStack {
                    Text(vm.appLanguage == .hebrew ? "שופט טניס" : "Tennis Ref")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal)

                Picker("Language", selection: $vm.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.rawValue).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: vm.appLanguage) { _ in
                    if vm.isListening {
                        vm.stop()
                        try? vm.start()
                    }
                }

                // Players Card
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(vm.appLanguage == .hebrew ? "שחקן 1" : "Player 1")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(vm.appLanguage == .hebrew ? "שם..." : "Name...", text: $vm.playerAName)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(vm.appLanguage == .hebrew ? "שחקן 2" : "Player 2")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(vm.appLanguage == .hebrew ? "שם..." : "Name...", text: $vm.playerBName)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(22)
                .padding(.horizontal)

                // Score Card
                VStack(spacing: 8) {
                    Text("\(pointLabelUI(vm.state.aPoint))  :  \(pointLabelUI(vm.state.bPoint))")
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text((vm.appLanguage == .hebrew ? "משחקונים " : "Games ") + "\(vm.state.aGames) : \(vm.state.bGames)")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .background(.ultraThinMaterial)
                .cornerRadius(28)
                .shadow(radius: 18)
                .padding(.horizontal)

                // Status Card
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.appLanguage == .hebrew ? "סטטוס" : "Status")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(vm.status)
                        .foregroundStyle(.white)
                        .font(.system(.body, design: .rounded))
                    if !vm.lastHeard.isEmpty {
                        Text((vm.appLanguage == .hebrew ? "שמעתי: " : "Heard: ") + vm.lastHeard)
                            .foregroundStyle(.white.opacity(0.75))
                            .font(.footnote)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial)
                .cornerRadius(22)
                .padding(.horizontal)

                // Controls
                VStack(spacing: 12) {
                    Button {
                        if vm.isListening { vm.stop() } else { try? vm.start() }
                    } label: {
                        Label(startStopTitle, systemImage: startStopIcon)
                            .font(.system(.headline, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background(vm.isListening ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
                    .foregroundStyle(.white)
                    .cornerRadius(18)

                    HStack(spacing: 12) {
                        Button {
                            vm.undo()
                        } label: {
                            Label(vm.appLanguage == .hebrew ? "בטל" : "Undo", systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .background(.orange.opacity(0.9))
                        .foregroundStyle(.white)
                        .cornerRadius(16)

                        Button {
                            vm.resetMatch()
                        } label: {
                            Label(vm.appLanguage == .hebrew ? "חדש" : "New", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .background(.blue.opacity(0.85))
                        .foregroundStyle(.white)
                        .cornerRadius(16)
                    }

                    Button {
                        vm.speakScore()
                    } label: {
                        Label(vm.appLanguage == .hebrew ? "הקרא תוצאה" : "Speak Score", systemImage: "speaker.wave.2.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .background(.white.opacity(0.18))
                    .foregroundStyle(.white)
                    .cornerRadius(16)
                }
                .padding(.horizontal)

                Spacer(minLength: 8)
            }
            .padding(.top, 14)
        }
        .onAppear { Task { await vm.requestPermissions() } }
    }
}

#Preview { ContentView() }
