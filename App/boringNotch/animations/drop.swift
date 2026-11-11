//
//  drop.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import Foundation
import SwiftUI


public class BoringAnimations {
    @Published var notchStyle: Style = .notch
    
    init() {
        self.notchStyle = .notch
    }
    
    var animation: Animation {
        if #available(macOS 14.0, *), notchStyle == .notch {
            Animation.easeOut(duration: 0.22)
        } else {
            Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.22)
        }
    }
    
    // TODO: Move all animations to this file
    
}
