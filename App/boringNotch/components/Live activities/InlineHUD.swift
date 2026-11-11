//
//  InlineHUDs.swift
//  boringNotch
//
//  Created by Richard Kunkli on 14/09/2024.
//

import SwiftUI
import Defaults

struct InlineHUD: View {
    static let iconWingWidth: CGFloat = 32
    static let levelWingWidth: CGFloat = 96
    // Shift the asymmetric surface so its empty middle stays over the camera.
    static var notchCenterOffset: CGFloat { (levelWingWidth - iconWingWidth) / 2 }
    @EnvironmentObject var vm: BoringViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var hoverAnimation: Bool
    @Default(.showClosedNotchHUDPercentage) private var showPercentage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Self.iconWingWidth, alignment: .center)
                .accessibilityHidden(true)

            Color.clear.frame(width: max(0, vm.closedNotchSize.width - 20))

            HStack(spacing: 6) {
                if type != .mic {
                    DraggableProgressBar(value: $value) { newValue in
                        switch type {
                        case .volume: VolumeManager.shared.setAbsolute(Float32(newValue))
                        case .brightness: BrightnessManager.shared.setAbsolute(value: Float32(newValue))
                        default: break
                        }
                    }
                }
                if showPercentage || type == .mic {
                    Text(type == .mic ? (value == 0 ? "Kapalı" : "Açık") : "\(Int((value * 100).rounded()))%")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 28, alignment: .trailing)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: Self.levelWingWidth)
        }
        .foregroundStyle(.white.opacity(0.92))
        .frame(height: max(24, vm.effectiveClosedNotchHeight + 2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var title: String {
        switch type {
        case .volume: "Sistem sesi"
        case .brightness: "Ekran parlaklığı"
        case .backlight: "Klavye aydınlatması"
        case .mic: "Mikrofon"
        default: ""
        }
    }

    private var symbol: String {
        if !icon.isEmpty { return icon }
        switch type {
        case .volume:
            if value == 0 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.68 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness: return value > 0.5 ? "sun.max.fill" : "sun.min.fill"
        case .backlight: return value > 0.5 ? "light.max" : "light.min"
        case .mic: return value == 0 ? "mic.slash.fill" : "mic.fill"
        default: return "circle"
        }
    }
}

#Preview {
    InlineHUD(type: .constant(.brightness), value: .constant(0.4), icon: .constant(""), hoverAnimation: .constant(false))
        .padding(.horizontal, 8)
        .background(Color.black)
        .padding()
        .environmentObject(BoringViewModel())
}
