//
//  LoginViewModel.swift
//  OCKSample
//
//  Created by Corey Baker on 11/24/20.
//  Copyright © 2020 Network Reconnaissance Lab. All rights reserved.
//

import CareKit
import CareKitStore
import ParseCareKit
import ParseSwift
import os.log
import WatchConnectivity

// swiftlint:disable function_parameter_count
@MainActor
class LoginViewModel: ObservableObject {

    // MARK: Public read, private write properties
    @Published private(set) var isLoggedIn: Bool? {
        willSet {
            /*
             Publishes a notification to subscribers whenever this value changes.
             This is what the @Published property wrapper gives you for free
             everytime you use it to wrap a property.
            */
            objectWillChange.send()
            if newValue != nil {
                self.sendUpdatedUserSessionTokenToWatch()
            }
        }
    }
    @Published private(set) var loginError: ParseError?

    init() {
        Task {
            await checkStatus()
        }
    }

    // MARK: Helpers (private)
    func checkStatus() async {
        do {
            _ = try await User.current()
            self.isLoggedIn = true
        } catch {
            self.isLoggedIn = false
        }
    }

    private func sendUpdatedUserSessionTokenToWatch() {
        Task {
            do {
                let message = try await Utility.getUserSessionForWatch()
                DispatchQueue.global(qos: .default).async {
                    // WCSession.default.sendMessage crashes when sending on MainActor
                    // so we call on a less important queue.
                    WCSession.default.sendMessage(
                        message,
                        replyHandler: nil,
                        errorHandler: { error in
                            Logger.remoteSessionDelegate.info("Could not send updated session token to watch: \(error)")
                        }
                    )
                }
            } catch {
                Logger.login.info("Could not get session token for watch: \(error)")
                return
            }
        }
    }

    private func finishCompletingSignIn(
        _ careKitPatient: OCKPatient? = nil
    ) async throws {
        if let careKitUser = careKitPatient {
            var user = try await User.current()
            guard let userType = careKitUser.userType,
                let remoteUUID = careKitUser.remoteClockUUID else {
                return
            }
            user.lastTypeSelected = userType.rawValue
            if user.userTypeUUIDs != nil {
                user.userTypeUUIDs?[userType.rawValue] = remoteUUID
            } else {
                user.userTypeUUIDs = [userType.rawValue: remoteUUID]
            }
            do {
                _ = try await user.save()
            } catch {
                Logger.login.info("Could not save updated user: \(error)")
            }
        }

        // For existing user login, wait for remote data to sync before
        // transitioning UI so onboarding status and tasks are available
        if careKitPatient == nil, let appDelegate = AppDelegateKey.defaultValue {
            appDelegate.parseRemote.automaticallySynchronizes = false
            try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                appDelegate.store.synchronize { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            appDelegate.parseRemote.automaticallySynchronizes = true
        }

        // Detection setup is intentionally deferred until here, AFTER any
        // initial sync above. Doing it earlier (e.g. inside setupRemotes)
        // races the cloud pull and can produce orphan outcomes that crash
        // CareKit when displayed.
        if let appDelegate = AppDelegateKey.defaultValue, let store = appDelegate.store {
            await appDelegate.startExerciseDetectionIfNeeded(store: store)
        }

        // Notify the SwiftUI view that the user is correctly logged in and to transition screens
        await checkStatus()

        // Setup installation to receive push notifications
        await Utility.updateInstallationWithDeviceToken()

        // Claim any pending Relationship rows addressed to this user's email
        // or phone before they had an account. Each match has its patientObjectId
        // / patientUsername filled in, ACL tightened, and the deferred
        // connection-request notification dispatched. Idempotent.
        await Relationship.linkPendingForCurrentUser()
    }

    private func savePatientAfterSignUp(
        _ type: UserType,
        firstName: String,
        lastName: String, email: String?
    ) async throws -> OCKPatient {

        let remoteUUID = UUID()
        do {
            try await Utility.setDefaultACL()
        } catch {
            Logger.login.error("Could not set defaultACL: \(error)")
        }

        guard let appDelegate = AppDelegateKey.defaultValue else {
            throw AppError.couldntBeUnwrapped
        }
        try await appDelegate.setupRemotes(uuid: remoteUUID)

        // Check if a patient already exists in this store (OCKStore only allows one per store).
        // This happens when the app is launched again after a previous anonymous/signup session.
        let existingPatients = (try? await appDelegate.store.fetchAnyPatients(
            query: OCKPatientQuery(for: Date())
        )) ?? []

        let savedPatient: OCKPatient
        if let existingPatient = existingPatients.first as? OCKPatient {
            Logger.login.info("Patient already exists in store, reusing existing patient")
            savedPatient = existingPatient
        } else {
            var newPatient = OCKPatient(
                remoteUUID: remoteUUID,
                id: remoteUUID.uuidString,
                givenName: firstName,
                familyName: lastName,
                email: email
            )
            newPatient.userType = type
            savedPatient = try await appDelegate.store.addPatient(newPatient)
        }

        // Use addContactsIfNotPresent so this is safe on retry/re-login (addAnyContact throws on duplicate)
        let newContact = OCKContact(
            id: savedPatient.id,
            name: savedPatient.name,
            carePlanUUID: nil
        )
        _ = try await appDelegate.store.addContactsIfNotPresent([newContact])

        let currentDate = Date()
        let startDate = daysInThePastToGenerateSampleData < 0 ? Calendar.current.date(
            byAdding: .day,
            value: daysInThePastToGenerateSampleData,
            to: currentDate
        )! : currentDate
        // Pass savedPatient.uuid so care plans are tied to this patient
        try await appDelegate.store.populateDefaultCarePlansTasksContacts(
            savedPatient.uuid,
            startDate: startDate
        )
        try await appDelegate.healthKitStore.populateDefaultHealthKitTasks(
            savedPatient.uuid,
            startDate: startDate
        )
        if startDate < currentDate {
            try await appDelegate.store.populateSampleOutcomes(
                startDate: startDate
            )
        }
        appDelegate.parseRemote.automaticallySynchronizes = true

        // Post notification to sync
        NotificationCenter.default.post(.init(name: Notification.Name(rawValue: Constants.requestSync)))
        Logger.login.info("Successfully added a new Patient")
        return savedPatient
    }

    // MARK: User intentional behavior
    /**
     Signs up the user *asynchronously*.

     This will also enforce that the username is not already taken.
     - parameter username: The username the person signing up.
     - parameter email: The email the person signing up.
     - parameter password: The password the person signing up.
     - parameter firstName: The first name of the person signing up.
     - parameter lastName: The last name of the person signing up.
    */
    func signup(
        _ type: UserType,
        username: String,
        password: String,
        firstName: String,
        lastName: String, email: String
    ) async {
        // swiftlint:disable:next line_length
        guard username.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.init(charactersIn: "_")).contains($0) }) else {
            // swiftlint:disable:next line_length
            self.loginError = ParseError(code: .otherCause, message: "Username can only contain letters, numbers, and underscores.")
            return
        }
        do {
            guard try await PCKUtility.isServerAvailable() else {
                Logger.login.error("Server health is not \"ok\"")
                return
            }
            try? await User.logout()

            var newUser = User()
            // Set any properties you want saved on the user befor logging in.
            newUser.username = username.lowercased()
            if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newUser.email = email.lowercased()
            }
            newUser.password = password
            let user = try await newUser.signup()
            Logger.login.info("Parse signup successful: \(user)")
            let patient = try await savePatientAfterSignUp(type,
                                                           firstName: firstName,
                                                           lastName: lastName,
                                                           email: email)
            try? await finishCompletingSignIn(patient)
        } catch {
            Logger.login.error("Error details: \(error)")
            guard let parseError = error as? ParseError else {
                return
            }
            switch parseError.code {
            case .usernameTaken:
                self.loginError = parseError

            case .userEmailTaken:
                self.loginError = parseError

            default:
                // swiftlint:disable:next line_length
                Logger.login.error("*** Error Signing up as user for Parse Server. Are you running parse-hipaa and is the initialization complete? Check http://localhost:1337 in your browser. If you are still having problems check for help here: https://github.com/netreconlab/parse-postgres#getting-started ***")
                self.loginError = parseError
            }
        }
    }

    /**
     Logs in the user *asynchronously*.

     The user must have already signed up.
     - parameter username: The username the person logging in.
     - parameter email: The email the person logging in.
     - parameter password: The password the person logging in.
    */
    func login(
        usernameOrEmail: String,
        password: String
    ) async {
        do {
            guard try await PCKUtility.isServerAvailable() else {
                Logger.login.error("Server health is not \"ok\"")
                return
            }
            let user: User
            if usernameOrEmail.contains("@") {
                user = try await User.login(email: usernameOrEmail.lowercased(), password: password)
            } else {
                user = try await User.login(username: usernameOrEmail.lowercased(), password: password)
            }
            Logger.login.info("Parse login successful: \(user, privacy: .private)")
            AppDelegateKey.defaultValue?.setFirstTimeLogin(true)
            do {
                try await Utility.setupRemoteAfterLogin()
                try await finishCompletingSignIn()
            } catch {
                Logger.login.error("Error saving the patient after login: \(error, privacy: .public)")
            }
        } catch {
            // swiftlint:disable:next line_length
            Logger.login.error("*** Error logging into Parse Server. If you are still having problems check for help here: https://github.com/netreconlab/parse-hipaa#getting-started ***")
            Logger.login.error("Error details: \(error)")
            guard let parseError = error as? ParseError else {
                return
            }
            self.loginError = parseError
        }
    }

    /**
     Logs in the user anonymously *asynchronously*.
    */
    func loginAnonymously() async {
        do {
            guard try await PCKUtility.isServerAvailable() else {
                Logger.login.error("Server health is not \"ok\"")
                return
            }
            let user = try await User.anonymous.login()
            Logger.login.info("Parse login anonymous successful: \(user)")
            // Only allow annonymous users to be patients.
            let patient = try await savePatientAfterSignUp(.patient,
                                                           firstName: "Anonymous",
                                                           lastName: "Login",
                                                           email: "Universal")
            try? await finishCompletingSignIn(patient)
        } catch {
            // swiftlint:disable:next line_length
            Logger.login.error("*** Error logging into Parse Server. If you are still having problems check for help here: https://github.com/netreconlab/parse-hipaa#getting-started ***")
            Logger.login.error("Error details: \(String(describing: error))")
            guard let parseError = error as? ParseError else {
                return
            }
            self.loginError = parseError
        }
    }

    /**
     Logs out the currently logged in person *asynchronously*.
    */
    func logout() async {
        self.loginError = nil
        await Utility.logoutAndResetAppState()
        await self.checkStatus()
    }
}
