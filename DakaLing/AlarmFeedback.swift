import AudioToolbox
import AVFoundation
import CoreHaptics
import Foundation

@MainActor
enum AlarmFeedback {
    /// One reminder rings and vibrates for this long. Stop cuts it off immediately.
    static let duration: TimeInterval = 30

    private static var engine: CHHapticEngine?
    private static var player: AVAudioPlayer?
    private static var hapticPlayer: CHHapticPatternPlayer?
    private static var endTask: Task<Void, Never>?
    private static var hapticTask: Task<Void, Never>?
    private static var playToken = 0
    private static var sessionReady = false

    static func prepare() {
        guard engine == nil else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = false
            engine.resetHandler = { try? engine.start() }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    /// Ringtone and vibration start together and both run for `duration`.
    static func preview(kind: ReminderKind) {
        stopPlayback()
        playToken += 1
        let token = playToken
        Task {
            await prepareSession()
            guard token == playToken else { return }
            startSound(kind)
            startHaptics(kind: kind, token: token)
            endTask = Task {
                try? await Task.sleep(for: .seconds(duration))
                guard !Task.isCancelled, token == playToken else { return }
                stopPlayback()
            }
        }
    }

    static func stop() {
        playToken += 1
        stopPlayback()
    }

    static func vibrate(kind: ReminderKind) {
        playToken += 1
        let token = playToken
        startHaptics(kind: kind, token: token)
    }

    private static func stopPlayback() {
        endTask?.cancel()
        endTask = nil
        hapticTask?.cancel()
        hapticTask = nil
        try? hapticPlayer?.stop(atTime: 0)
        hapticPlayer = nil
        player?.stop()
        player = nil
    }

    /// Category and activation are synchronous. Doing them on the main thread blocks taps.
    private static func prepareSession() async {
        guard !sessionReady else { return }
        let ready = await Task.detached { () -> Bool in
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
                return true
            } catch {
                return false
            }
        }.value
        if ready { sessionReady = true }
    }

    private static func startSound(_ kind: ReminderKind) {
        let name = kind.soundFile.replacingOccurrences(of: ".wav", with: "")
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            // A posted notification still plays its own sound.
        }
    }

    private static func startHaptics(kind: ReminderKind, token: Int) {
        let sharpness: Float = kind == .arrive ? 0.85 : 0.35
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallbackVibrate(token: token)
            return
        }
        if engine == nil { prepare() }
        guard let engine else {
            fallbackVibrate(token: token)
            return
        }
        do {
            try engine.start()
            let pattern = try repeatingPattern(sharpness: sharpness)
            let hapticPlayer = try engine.makePlayer(with: pattern)
            self.hapticPlayer = hapticPlayer
            try hapticPlayer.start(atTime: 0)
        } catch {
            fallbackVibrate(token: token)
        }
    }

    private static func repeatingPattern(sharpness: Float) throws -> CHHapticPattern {
        var events: [CHHapticEvent] = []
        var time = 0.0
        while time < duration {
            events.append(
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.75),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                    ],
                    relativeTime: time,
                    duration: 0.28
                )
            )
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                    ],
                    relativeTime: time
                )
            )
            time += 0.45
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    private static func fallbackVibrate(token: Int) {
        hapticTask?.cancel()
        hapticTask = Task {
            let start = Date()
            while !Task.isCancelled, token == playToken, Date().timeIntervalSince(start) < duration {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
    }
}
