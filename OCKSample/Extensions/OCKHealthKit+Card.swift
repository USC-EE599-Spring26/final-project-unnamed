//
//  OCKHealthKit+Card.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/2/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import Foundation
import CareKitStore

extension OCKHealthKitTask: CareTask {

}

// extension OCKHealthKitTask {
//
//    var card: CareKitCard {
//        get {
//            guard let cardInfo = userInfo?[Constants.card],
//                  let careKitCard = CareKitCard(rawValue: cardInfo) else {
//                return .grid // Default card if none was saved
//            }
//            return careKitCard // Saved card type
//        }
//        set {
//            if userInfo == nil {
//                // Initialize userInfo with empty dictionary
//                userInfo = .init()
//            }
//            // Set the new card type
//            userInfo?[Constants.card] = newValue.rawValue
//        }
//    }
// }
