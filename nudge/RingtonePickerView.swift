import SwiftUI

struct RingtonePickerView: View {
    @Binding var selectedRingtone: String
    @StateObject private var ringtoneManager = RingtoneManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                ForEach(RingtoneManager.Ringtone.allCases) { ringtone in
                    RingtoneRow(
                        ringtone: ringtone,
                        isSelected: selectedRingtone == ringtone.rawValue,
                        isPlaying: ringtoneManager.currentlyPlaying == ringtone
                    ) {
                        ringtoneManager.preview(ringtone)
                    } onSelect: {
                        selectedRingtone = ringtone.rawValue
                        ringtoneManager.stop()
                    }
                }
            } header: {
                Text("Tap to preview, select to set")
            } footer: {
                Text("This sound will play when reminder notifications are delivered, including on the lock screen.")
            }
        }
        .navigationTitle("Reminder Sound")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            ringtoneManager.stop()
        }
    }
}

struct RingtoneRow: View {
    let ringtone: RingtoneManager.Ringtone
    let isSelected: Bool
    let isPlaying: Bool
    let onPreview: () -> Void
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .blue : .secondary)
                .font(.title2)
                .onTapGesture {
                    onSelect()
                }
            
            Text(ringtone.displayName)
                .padding(.leading, 8)
            
            Spacer()
            
            Button {
                onPreview()
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isPlaying ? .red : .blue)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPreview()
        }
    }
}
