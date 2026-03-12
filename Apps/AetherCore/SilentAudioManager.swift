import Foundation
import AVFoundation
import os.log

class SilentAudioManager {
    static let shared = SilentAudioManager()
    
    private var audioPlayer: AVAudioPlayer?
    private let log = OSLog(subsystem: "com.7fei.Aether", category: "SilentAudio")
    
    private init() {
        setupSilentAudio()
    }
    
    @discardableResult
    private func setupSilentAudio() -> Bool {
        // Generate a minimal valid WAV file data for silent audio
        let sampleRate: Int32 = 44100
        let channels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate: Int32 = sampleRate * Int32(channels) * Int32(bitsPerSample) / 8
        let blockAlign: Int16 = channels * bitsPerSample / 8
        let dataSize: Int32 = sampleRate * Int32(blockAlign) // 1 second of silence
        let chunkSize: Int32 = 36 + dataSize
        
        var wavData = Data()
        // RIFF header
        wavData.append(contentsOf: "RIFF".utf8)
        wavData.append(withUnsafeBytes(of: chunkSize.littleEndian) { Data($0) })
        wavData.append(contentsOf: "WAVE".utf8)
        // fmt subchunk
        wavData.append(contentsOf: "fmt ".utf8)
        wavData.append(withUnsafeBytes(of: Int32(16).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: Int16(1).littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        // data subchunk
        wavData.append(contentsOf: "data".utf8)
        wavData.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        wavData.append(Data(count: Int(dataSize))) // Zeros
        
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.volume = 0.0 // Ensure absolute silence
            audioPlayer?.prepareToPlay()
            return true
        } catch {
            os_log("Failed to initialize AVAudioPlayer: %{public}@", log: self.log, type: .error, error.localizedDescription)
            audioPlayer = nil
            return false
        }
    }
    
    func start() {
        if audioPlayer == nil {
            _ = setupSilentAudio()
        }
        guard let player = audioPlayer, !player.isPlaying else { return }
        os_log("Starting silent audio to lock Now Playing focus", log: self.log, type: .info)
        // Set volume to 0.0 to guarantee silent output regardless of system state
        player.volume = 0.0
        player.play()
    }
    
    func stop() {
        guard let player = audioPlayer, player.isPlaying else { return }
        os_log("Stopping silent audio", log: self.log, type: .info)
        player.pause()
    }
}
