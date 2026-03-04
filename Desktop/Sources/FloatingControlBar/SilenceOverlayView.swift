import SwiftUI

/// Overlay shown when PTT finishes with no speech detected.
/// Displays a mic picker and live audio level so the user can verify their mic works.
struct SilenceOverlayView: View {
    @ObservedObject private var deviceManager = AudioDeviceManager.shared
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "mic.slash.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 13))
                Text("Didn't catch that — try a different mic?")
                    .scaledFont(size: 12, weight: .medium)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }

            if !deviceManager.devices.isEmpty {
                Picker("Microphone", selection: Binding(
                    get: { deviceManager.selectedDeviceUID ?? "" },
                    set: { deviceManager.selectedDeviceUID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("System Default")
                        .tag("")
                    ForEach(deviceManager.devices) { device in
                        Text(device.name)
                            .tag(device.uid)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                .scaledFont(size: 12)
            }

            AudioLevelBarsSettingsView(level: deviceManager.currentAudioLevel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
                )
        )
        .padding(8)
        .onAppear { deviceManager.startLevelMonitoring() }
        .onDisappear { deviceManager.stopLevelMonitoring() }
    }
}
