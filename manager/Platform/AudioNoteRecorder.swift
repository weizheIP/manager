import AVFoundation
import Observation

@MainActor @Observable
final class AudioNoteRecorder: NSObject, AVAudioRecorderDelegate {
    private(set) var recording = false
    private(set) var requesting = false
    private(set) var url: URL?
    var errorMessage: String?
    private var recorder: AVAudioRecorder?
    private var observer: NSObjectProtocol?

    func start() async {
        guard !recording && !requesting else { return }
        errorMessage = nil
        requesting = true
        defer { requesting = false }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "未允许麦克风。可在系统设置中允许后再录音。"; return
        }
        discard()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let location = URL.temporaryDirectory.appending(path: "chidi-recording-\(UUID().uuidString).m4a")
            let audio = try AVAudioRecorder(url: location, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue])
            audio.delegate = self
            recorder = audio
            url = location
            guard audio.record(forDuration: 3600) else { throw ChidiDataError.invalid("无法开始录音。") }
            recording = true
            observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
                guard let recorder = self else { return }
                Task { @MainActor in recorder.stop() }
            }
        } catch { errorMessage = error.localizedDescription; discard() }
    }

    func stop() {
        recorder?.stop()
        recording = false
        if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func discard() {
        stop()
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        recorder = nil
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor in
            guard self.recorder.map(ObjectIdentifier.init) == identity else { return }
            self.stop()
            if !flag { self.errorMessage = "录音意外中断，保存前请试听检查。" }
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let message = error?.localizedDescription ?? "音频编码失败"
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor in
            guard self.recorder.map(ObjectIdentifier.init) == identity else { return }
            self.stop(); self.errorMessage = message
        }
    }
}
