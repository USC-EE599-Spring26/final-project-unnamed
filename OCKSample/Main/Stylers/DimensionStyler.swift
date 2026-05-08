//
//  DimensionStyler.swift
//  OCKSample
//
//  Created by Student on 3/4/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitUI
import UIKit

struct DimensionStyler: OCKDimensionStyler {
    // Decrease symbol point size 1 (largest)
    var symbolPointSize1: CGFloat { 28 }

    // Increase stack spacing
    var stackSpacing1: CGFloat { 10 }

    // Decrease standard line width
    var lineWidth1: CGFloat { 2.0 }
}
