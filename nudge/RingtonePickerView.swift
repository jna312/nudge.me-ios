import SwiftUI

struct RingtonePickerView: View {
    @Binding var selectedRingtone: String
    @StateObject private var ringtoneManager = RingtoneManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach(RingtoneManager.ringtonesByCategory, id: \.category) { group in
                Section {
                    ForEach(group.ringtones) { ringtone in
                        RingtoneRow(
                            ringtone: ringtone,
                            isSelected: selectedRingtone == ringtone.id,
                            isPlaying: ringtoneManager.currentlyPlaying?.id == ringtone.id
                        ) {
                            ringtoneManager.preview(ringtone)
                        } onSelect: {
                            selectedRingtone = ringtone.id
                            ringtoneManager.stop()
                        }
                    }
                } header: {
                    Text(group.category.rawValue)
                } footer: {
                    if group.category == .system {
                        Text("Uses your device's notification sound setting")
                    } else if group.category == .appSounds {
                        Text("Original Nudge notification sounds")
                    }
                }
            }
        }
        .navigationTitle("Reminder Sound")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if ringtoneManager.isPlaying {
                    Button {
                        ringtoneManager.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
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
            Button {
                onSelect()
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
            
            Text(ringtone.displayName)
                .padding(.leading, 8)
                .foregroundStyle(.primary)
            
            Spacer()
            
            Button {
                onPreview()
            } label: {
                Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle")
                    .font(.title2)
                    .foregroundStyle(isPlaying ? .red : .blue)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        RingtonePickerView(selectedRingtone: .constant("standard"))
    }
}
