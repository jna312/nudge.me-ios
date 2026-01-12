import SwiftUI
import Combine
import AVFoundation

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @StateObject private var soundPlayer = SoundPreviewPlayer()
    @State private var volumeDebounceTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Daily closeout") {
                DatePicker(
                    "Closeout time",
                    selection: Binding(
                        get: { dateFromMinutes(settings.dailyCloseoutMinutes) },
                        set: { settings.dailyCloseoutMinutes = minutesFromMidnight($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                Text("Only triggers if you created reminders for that day.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Defaults") {
                DatePicker(
                    "Date-only default time",
                    selection: Binding(
                        get: { dateFromMinutes(settings.defaultDateOnlyMinutes) },
                        set: { settings.defaultDateOnlyMinutes = minutesFromMidnight($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )

                Text("If you don't specify a time, we'll automatically set the reminder for \(formattedTime(from: settings.defaultDateOnlyMinutes)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(NotificationSoundOption.allCases) { option in
                    Button {
                        settings.notificationSound = option.rawValue
                        playPreviewSound()
                    } label: {
                        HStack {
                            Text(option.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if settings.notificationSound == option.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    
                    Slider(
                        value: $settings.notificationVolume,
                        in: 0...1
                    )
                    .onChange(of: settings.notificationVolume) { _, _ in
                        playPreviewSoundDebounced()
                    }
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Notification Sound")
            } footer: {
                if settings.notificationSound == "silent" {
                    Text("Notifications will be silent.")
                } else {
                    Text("Volume: \(Int(settings.notificationVolume * 100))%")
                }
            }

            Section("Writing style") {
                Picker("Reminder text", selection: $settings.writingStyle) {
                    Text("Sentence Case").tag("sentence")
                    Text("Title Case").tag("title")
                    Text("ALL CAPS").tag("caps")
                }
            }

            Section("Debug") {
                Button("Reset onboarding") {
                    settings.didCompleteOnboarding = false
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Settings")
        .onDisappear {
            volumeDebounceTask?.cancel()
            soundPlayer.stop()
        }
    }
    
    private func playPreviewSoundDebounced() {
        volumeDebounceTask?.cancel()
        volumeDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            guard !Task.isCancelled else { return }
            await MainActor.run {
                playPreviewSound()
            }
        }
    }
    
    private func playPreviewSound() {
        guard let option = NotificationSoundOption(rawValue: settings.notificationSound),
              option != .silent else { return }
        
        soundPlayer.play(sound: option, volume: Float(settings.notificationVolume))
    }

    private func minutesFromMidnight(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func dateFromMinutes(_ m: Int) -> Date {
        let h = m / 60
        let min = m % 60
        return Calendar.current.date(bySettingHour: h, minute: min, second: 0, of: Date())!
    }

    private func formattedTime(from minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        let date = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())!
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Sound Preview Player

class SoundPreviewPlayer: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    
    func play(sound: NotificationSoundOption, volume: Float) {
        guard sound != .silent else { return }
        
        // Stop any existing playback
        stop()
        
        // Configure audio session for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
        
        // Generate audio data for the selected sound
        let audioData = generateAudioData(for: sound)
        
        do {
            audioPlayer = try AVAudioPlayer(data: audioData, fileTypeHint: AVFileType.wav.rawValue)
            audioPlayer?.volume = volume
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            print("Audio player error: \(error)")
        }
    }
    
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    private func generateAudioData(for sound: NotificationSoundOption) -> Data {
        let sampleRate: Double = 44100
        let duration: Double
        let tones: [(frequency: Double, start: Double, length: Double)]
        
        switch sound {
        case .default:
            duration = 0.5
            tones = [(880, 0, 0.25), (1100, 0.25, 0.25)]
        case .triTone:
            duration = 0.6
            tones = [(1046.5, 0, 0.2), (1318.5, 0.2, 0.2), (1568, 0.4, 0.2)]
        case .chime:
            duration = 0.6
            tones = [(659.25, 0, 0.6)]
        case .pulse:
            duration = 0.5
            tones = [(880, 0, 0.12), (880, 0.17, 0.12), (880, 0.34, 0.12)]
        case .synth:
            duration = 0.6
            tones = [(523.25, 0, 0.15), (659.25, 0.15, 0.15), (783.99, 0.3, 0.15), (1046.5, 0.45, 0.15)]
        case .silent:
            duration = 0.1
            tones = []
        }
        
        let numSamples = Int(sampleRate * duration)
        var samples = [Int16](repeating: 0, count: numSamples)
        
        // Generate tones
        for tone in tones {
            let startSample = Int(tone.start * sampleRate)
            let toneSamples = Int(tone.length * sampleRate)
            
            for i in 0..<toneSamples {
                let sampleIndex = startSample + i
                guard sampleIndex < numSamples else { break }
                
                let t = Double(i) / sampleRate
                let progress = Double(i) / Double(toneSamples)
                
                // ADSR envelope: attack 10%, sustain 70%, release 20%
                let envelope: Double
                if progress < 0.1 {
                    envelope = progress / 0.1 // Attack
                } else if progress < 0.8 {
                    envelope = 1.0 // Sustain
                } else {
                    envelope = (1.0 - progress) / 0.2 // Release
                }
                
                let sample = sin(2.0 * Double.pi * tone.frequency * t) * envelope * 0.7
                let existingValue = Int(samples[sampleIndex])
                let newValue = Int(sample * Double(Int16.max / 2))
                samples[sampleIndex] = Int16(clamping: existingValue + newValue)
            }
        }
        
        // Create WAV file data
        return createWAVData(samples: samples, sampleRate: Int(sampleRate))
    }
    
    private func createWAVData(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        
        let numChannels: Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate = Int32(sampleRate * Int(numChannels) * Int(bitsPerSample) / 8)
        let blockAlign = Int16(numChannels * bitsPerSample / 8)
        let dataSize = Int32(samples.count * Int(blockAlign))
        let fileSize = Int32(36 + dataSize)
        
        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)
        
        // fmt subchunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: Int32(16).littleEndian) { Array($0) }) // Subchunk1Size
        data.append(contentsOf: withUnsafeBytes(of: Int16(1).littleEndian) { Array($0) }) // AudioFormat (PCM)
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: Int32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
        
        // data subchunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
        
        // Audio samples
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample.littleEndian) { Array($0) })
        }
        
        return data
    }
}

