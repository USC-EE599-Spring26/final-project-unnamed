//
//  CardTask.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/3/3.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

protocol CareTask {
    var id: String { get }
    var userInfo: [String: String] { get set }

    var card: CareKitCard { get set }
}

extension CareTask {

}
