//
//  Consent.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/3/24.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import Foundation

// swiftlint:disable line_length

/*
 TODOx: The informedConsentHTML property allows you to display HTML
 on an ResearchKit Survey. Modify the consent so it properly
 represents the usecase of your application.
 */

let informedConsentHTML = """
    <!DOCTYPE html>
    <html lang="en" xmlns="http://www.w3.org/1999/xhtml">
    <head>
        <meta name="viewport" content="width=400, user-scalable=no">
        <meta charset="utf-8" />
        <style type="text/css">
            ul, p, h1, h3 {
                text-align: left;
            }
        </style>
    </head>
    <body>
        <h1>Informed Consent</h1>
        <h3>Study Expectations</h3>
        <ul>
            <li>You will complete an onboarding process to review consent and confirm eligibility before using the app.</li>
            <li>You will be asked to complete daily tasks, including but not limited to check-in surveys and range-of-motion activities.</li>
            <li>The app may collect health-related data, including but not limited to sleep, heart rate, and physical activity or motion data.</li>
            <li>The app may send notifications to remind you to complete assigned tasks.</li>
            <li>Your data will be used to analyze behavioral patterns and support adaptive feedback within the application.</li>
            <li>The study will continue for the duration of the project.</li>
            <li>Your information will be kept private and secure.</li>
            <li>You can withdraw from the study at any time.</li>
        </ul>

        <h3>Eligibility Requirements</h3>
        <ul>
            <li>Participants must be at least 13 years old.</li>
            <li>Participants under 18 must have parental or guardian consent.</li>
            <li>Must be able to read and understand English.</li>
            <li>Must be the only user of the device on which you are participating in the study.</li>
            <li>Must be able to provide consent.</li>
        </ul>
        <p>By signing below, I acknowledge that I have read this consent carefully, that I understand all of its terms, and that I enter into this study voluntarily. I understand that my information will only be used and disclosed for the purposes described in the consent and I can withdraw from the study at any time.</p>
        <p>Please sign using your finger below.</p>
        <br>
    </body>
    </html>
    """
