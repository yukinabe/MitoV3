import AVFoundation
import Foundation

/// Central sound + music playback for the game.
///
/// Design notes:
/// - SFX use a small voice pool per clip so rapid taps / overlapping hits don't
///   cut each other off.
/// - Music loops politely: we use the `.ambient` session category so the ringer
///   switch is respected, and we never start our own BGM on top of audio the
///   user is already playing (Spotify, podcasts, etc).
/// - All clips are preloaded off the main thread to avoid first-play hitches.
final class AudioManager {
    static let shared = AudioManager()

    /// One-shot sound effects. Raw values map to `Sounds/<name>.wav`.
    enum Sound: String, CaseIterable {
        case cardShow = "card_show"
        case gradeAgain = "grade_again"
        case gradeHard = "grade_hard"
        case gradeGood = "grade_good"
        case gradeEasy = "grade_easy"
        case uiTap = "ui_tap"
        case uiBack = "ui_back"
        case hitBasic = "hit_basic"
        case hitSkill = "hit_skill"
        case hitUltimate = "hit_ultimate"
        case crit = "crit"
        case enemyDeath = "enemy_death"
        case enemyAttack = "enemy_attack"
        case castDamage = "cast_damage"
        case castDamageUlt = "cast_damage_ult"
        case castSupport = "cast_support"
        case castSupportUlt = "cast_support_ult"
        case victory = "victory"
        case defeat = "defeat"
        case reward = "reward"
    }

    /// Looping background tracks.
    enum Music: String {
        case battle = "bgm_battle"
        case home = "bgm_home"
    }

    // MARK: - Settings (persisted)

    var sfxEnabled: Bool {
        get { defaults.object(forKey: "audio.sfx") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "audio.sfx") }
    }
    var musicEnabled: Bool {
        get { defaults.object(forKey: "audio.music") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "audio.music")
            if newValue { startMusic(lastMusic ?? .home) } else { stopMusic() }
        }
    }

    /// Master volume (0...1) scaling all SFX and music. Persisted.
    /// Stored under "audio.master"; tolerant of Float/Double writers (e.g. @AppStorage).
    var masterVolume: Float {
        get { defaults.object(forKey: "audio.master") == nil ? 0.8 : defaults.float(forKey: "audio.master") }
        set {
            let v = min(max(newValue, 0), 1)
            defaults.set(v, forKey: "audio.master")
            queue.async { [weak self] in
                guard let self, let p = self.musicPlayer else { return }
                p.volume = self.musicBaseVolume * v
            }
        }
    }

    private let defaults = UserDefaults.standard
    private let maxVoices = 5
    private var pools: [String: [AVAudioPlayer]] = [:]
    private var musicPlayer: AVAudioPlayer?
    private var currentMusic: Music?
    private var lastMusic: Music?
    private var musicBaseVolume: Float = 0.55
    private var configured = false
    private let queue = DispatchQueue(label: "mito.audio", qos: .userInitiated)

    private init() {}

    // MARK: - Lifecycle

    /// Configure the audio session and warm up all clips. Call once at launch.
    func prepare() {
        configureSession()
        queue.async { [weak self] in
            guard let self else { return }
            for sound in Sound.allCases {
                _ = self.player(for: sound.rawValue) // warm the first voice
            }
        }
    }

    private func configureSession() {
        guard !configured else { return }
        configured = true
        let session = AVAudioSession.sharedInstance()
        // `.ambient` respects the mute switch and mixes with other audio.
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    // MARK: - SFX

    /// Play a one-shot effect. `volume` is 0...1, `pitch`/`pan` optional flavor.
    func play(_ sound: Sound, volume: Float = 1.0, pan: Float = 0.0) {
        guard sfxEnabled else { return }
        let master = masterVolume
        queue.async { [weak self] in
            guard let self, let p = self.freeVoice(for: sound.rawValue) else { return }
            p.volume = volume * master
            p.pan = pan
            p.currentTime = 0
            p.play()
        }
    }

    // MARK: - Music

    func startMusic(_ track: Music, volume: Float = 0.55) {
        lastMusic = track
        guard musicEnabled else { return }
        // Don't talk over the user's own music.
        if AVAudioSession.sharedInstance().isOtherAudioPlaying { return }
        let master = masterVolume
        queue.async { [weak self] in
            guard let self else { return }
            if self.currentMusic == track, self.musicPlayer?.isPlaying == true { return }
            guard let url = Self.url(for: track.rawValue) else { return }
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.numberOfLoops = -1
                p.volume = 0
                p.prepareToPlay()
                p.play()
                self.musicPlayer?.stop()
                self.musicPlayer = p
                self.currentMusic = track
                self.musicBaseVolume = volume
                self.fade(p, to: volume * master, over: 1.2)
            } catch {
                // Non-fatal: silence is acceptable if a track fails to load.
            }
        }
    }

    func stopMusic() {
        queue.async { [weak self] in
            guard let self, let p = self.musicPlayer else { return }
            self.currentMusic = nil
            self.fade(p, to: 0, over: 0.6) { p.stop() }
        }
    }

    private func fade(_ player: AVAudioPlayer, to target: Float, over seconds: TimeInterval,
                      then completion: (() -> Void)? = nil) {
        let steps = 24
        let start = player.volume
        let dt = seconds / Double(steps)
        for i in 1...steps {
            queue.asyncAfter(deadline: .now() + dt * Double(i)) {
                player.volume = start + (target - start) * Float(i) / Float(steps)
                if i == steps { completion?() }
            }
        }
    }

    // MARK: - Voice pool

    private func freeVoice(for name: String) -> AVAudioPlayer? {
        var pool = pools[name] ?? []
        if let idle = pool.first(where: { !$0.isPlaying }) { return idle }
        guard pool.count < maxVoices, let fresh = makePlayer(for: name) else {
            return pool.first // all busy: steal the oldest
        }
        pool.append(fresh)
        pools[name] = pool
        return fresh
    }

    private func player(for name: String) -> AVAudioPlayer? {
        if let existing = pools[name]?.first { return existing }
        guard let p = makePlayer(for: name) else { return nil }
        pools[name] = [p]
        return p
    }

    private func makePlayer(for name: String) -> AVAudioPlayer? {
        guard let url = Self.url(for: name) else { return nil }
        let p = try? AVAudioPlayer(contentsOf: url)
        p?.prepareToPlay()
        return p
    }

    private static func url(for name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: "wav")
    }
}
