import SwiftUI
import UIKit

/// One accessible control handles both tap-to-toggle and hold-to-record.
/// Tracking stays in UIKit so a long press can never also dispatch a tap.
struct CaptureMicButton: View {
    let isRecording: Bool
    let isBusy: Bool
    let onTap: () -> Void
    let onHoldStart: () -> Void
    let onHoldEnd: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(NudgeDesign.accent.opacity(isRecording ? 0.15 : 0.05))
                .frame(width: 132, height: 132)
            Circle()
                .fill(RadialGradient(
                    colors: isRecording
                        ? [Color(red: 0.70, green: 0.75, blue: 1), Color(red: 0.33, green: 0.39, blue: 0.88), Color(red: 0.16, green: 0.20, blue: 0.53)]
                        : [Color(red: 0.72, green: 0.80, blue: 1), Color(red: 0.40, green: 0.46, blue: 0.94), Color(red: 0.20, green: 0.27, blue: 0.65)],
                    center: .init(x: 0.27, y: 0.17), startRadius: 0, endRadius: 115))
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: NudgeDesign.accent.opacity(0.25), radius: 16, y: 7)
                .frame(width: 108, height: 108)
            if isBusy {
                ProgressView().tint(.white).scaleEffect(1.3)
            } else {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: isRecording ? 28 : 35, weight: .medium))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            MicTrackingControl(
                label: isBusy ? String(localized: "Finishing reminder") : isRecording
                    ? String(localized: "Stop recording") : String(localized: "Start recording"),
                hint: String(localized: "Tap to start or stop. Hold to record, then release to finish."),
                enabled: !isBusy, onTap: onTap, onHoldStart: onHoldStart, onHoldEnd: onHoldEnd)
                .frame(width: 118, height: 118)
        }
        .frame(width: 132, height: 132)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isRecording)
        .accessibilityElement(children: .contain)
    }
}

private struct MicTrackingControl: UIViewRepresentable {
    var label: String
    var hint: String
    var enabled: Bool
    var onTap: () -> Void
    var onHoldStart: () -> Void
    var onHoldEnd: () -> Void

    func makeUIView(context: Context) -> MicControl { MicControl() }

    func updateUIView(_ view: MicControl, context: Context) {
        view.accessibilityLabel = label
        view.accessibilityHint = hint
        view.accessibilityIdentifier = "capture.microphone"
        view.isEnabled = enabled
        view.onTap = onTap
        view.onHoldStart = onHoldStart
        view.onHoldEnd = onHoldEnd
    }

    static func dismantleUIView(_ view: MicControl, coordinator: ()) {
        view.cancelTracking(with: nil)
    }
}

final class MicControl: UIControl {
    var onTap: (() -> Void)?
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?
    private var holdTimer: Timer?
    private var isHolding = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        holdTimer?.invalidate()
        isHolding = false
        holdTimer = Timer(timeInterval: 0.28, repeats: false) { [weak self] _ in
            guard let self, self.isTracking, self.isEnabled else { return }
            self.isHolding = true
            self.onHoldStart?()
        }
        if let holdTimer { RunLoop.main.add(holdTimer, forMode: .common) }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        holdTimer?.invalidate()
        holdTimer = nil
        let wasHolding = isHolding
        isHolding = false
        if wasHolding {
            onHoldEnd?()
        } else if isEnabled, let touch, bounds.contains(touch.location(in: self)) {
            onTap?()
        }
    }

    override func cancelTracking(with event: UIEvent?) {
        holdTimer?.invalidate()
        holdTimer = nil
        if isHolding {
            isHolding = false
            onHoldEnd?()
        }
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        onTap?()
        return true
    }
}
