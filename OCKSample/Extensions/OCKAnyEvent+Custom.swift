//
//  OCKAnyEvent+Custom.swift
//  OCKSample
//
//  Created by Student on 4/7/26.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore

extension OCKAnyEvent {

    func answer(kind: String) -> Double {
        let values = outcome?.values ?? []
        let match = values.first(where: { $0.kind == kind })
        return match?.doubleValue ?? 0
    }
}
