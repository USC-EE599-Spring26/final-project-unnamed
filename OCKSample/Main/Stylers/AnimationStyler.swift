//
//  AnimationStyler.swift
//  OCKSample
//
//  Created by Student on 3/4/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitUI
import UIKit

struct AnimationStyler: OCKAnimationStyler {
    // Slow down the animation duration for state changes
    var stateChangeDuration: TimeInterval { 0.5 }
}
