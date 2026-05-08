//
//  AppearanceStyler.swift
//  OCKSample
//
//  Created by Student on 3/4/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitUI
import UIKit

struct AppearanceStyler: OCKAppearanceStyler {
    // Make shadow darker
    var shadowOpacity1: Float { 0.3 }

    // Increase corner radius (rounder)
    var cornerRadius1: CGFloat { 18 }

    // Shift shadow further down
    var shadowOffset1: CGSize { CGSize(width: 0, height: 4) }
}
