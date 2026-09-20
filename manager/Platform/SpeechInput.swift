import AVFoundation
import Observation
import Speech

@MainActor @Observable
final class SpeechInput {
    private(set) var text = ""
    private(set) var listening = false
    private(set) var requesting = false
    private(set) var finishing = false
    var errorMessage: String?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var activeID = UUID()
    private var timeout: Task<Void, Never>?

    func start() async {
        guard !listening && !requesting && !finishing else { return }
        stop()
        let generation = UUID(); activeID = generation
        requesting = true
        errorMessage = nil
        defer { requesting = false }
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard activeID == generation else { return }
        guard speechAllowed else { errorMessage = "未允许语音识别。可在系统设置中允许，或直接输入文字。"; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            errorMessage = "当前设备的中文离线语音识别尚不可用，请检查系统语言资源或直接输入文字。"; return
        }
        guard await AVAudioApplication.requestRecordPermission() else { errorMessage = "未允许麦克风，请在系统设置中允许后重试。"; return }
        guard activeID == generation else { return }
        text = ""
        let id = UUID(); activeID = id
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 && format.channelCount > 0 else { throw ChidiDataError.invalid("没有可用的麦克风输入。") }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.engine = engine; self.request = request
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let transcript = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true
                let message = error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.activeID == id else { return }
                    if let transcript { self.text = transcript }
                    if finished || message != nil {
                        self.stop()
                        if let message { self.errorMessage = "识别已停止：\(message)；已识别文字仍可修改。" }
                    }
                }
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            engine.prepare()
            try engine.start()
            listening = true
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        } catch { stop(); errorMessage = error.localizedDescription }
    }

    /// Stop the microphone immediately, but allow the recognizer to return its final tail.
    func finish() {
        guard listening else { return }
        timeout?.cancel()
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil
        request?.endAudio()
        listening = false; finishing = true
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        activeID = UUID()
        timeout?.cancel(); timeout = nil
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        recognition?.cancel()
        engine = nil; request = nil; recognition = nil; listening = false; finishing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
