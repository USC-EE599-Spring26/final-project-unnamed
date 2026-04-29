//
//  PatientManagementViewModel.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import CareKitStore
import Foundation
import ParseSwift
import os.log

@MainActor
class PatientManagementViewModel: ObservableObject {

    struct PatientRow: Identifiable {
        let id: String                      // Relationship.objectId
        let username: String
        let displayName: String
        let email: String?
        let phoneNumber: String?
        let status: String
        let relationshipObjectId: String
        let patientObjectId: String
    }

    struct UnlinkedPendingRequest: Identifiable {
        let id: String
        let displayName: String
        let email: String?
        let phone: String?
        let relationshipObjectId: String
    }

    struct ContactItem: Identifiable {
        let id: String                      // OCKAnyContact.id
        let displayName: String
        let email: String?
        let phone: String?
        let userObjectId: String?
        let username: String?
        var connectionStatus: String?
    }

    @Published var acceptedPatients: [PatientRow] = []
    @Published var pendingPatients: [PatientRow] = []
    @Published var pendingUnlinked: [UnlinkedPendingRequest] = []
    @Published var isLoading   = false
    @Published var errorMessage: String?

    @Published var contactItems: [ContactItem] = []
    @Published var contactFilter    = ""
    @Published var isLoadingContacts = false
    @Published var isSending        = false

    var filteredContacts: [ContactItem] {
        guard !contactFilter.isEmpty else { return contactItems }
        let lower = contactFilter.lowercased()
        return contactItems.filter { item in
            item.displayName.lowercased().contains(lower)
            || (item.email?.lowercased().contains(lower) ?? false)
            || (item.phone?.lowercased().contains(lower) ?? false)
        }
    }

    func fetchPatients() async {
        guard let currentUser = try? await User.current(),
              let myObjectId = currentUser.objectId else {
            acceptedPatients = []
            pendingPatients  = []
            pendingUnlinked  = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        let relationships = (try? await Relationship
            .query("doctorObjectId" == myObjectId)
            .find()) ?? []

        var accepted: [PatientRow] = []
        var pendingLinked: [PatientRow] = []
        var unlinked: [UnlinkedPendingRequest] = []

        for rel in relationships {
            guard let relId  = rel.objectId,
                  let status = rel.status else { continue }

            let isLinked = (rel.patientObjectId?.isEmpty == false)
                && (rel.patientUsername?.isEmpty == false)

            if isLinked {
                let username = rel.patientUsername!     // swiftlint:disable:this force_unwrapping
                let pid      = rel.patientObjectId!     // swiftlint:disable:this force_unwrapping
                let row = PatientRow(
                    id: relId,
                    username: username,
                    displayName: username.capitalized,
                    email: rel.patientEmail,
                    phoneNumber: rel.patientPhone,
                    status: status,
                    relationshipObjectId: relId,
                    patientObjectId: pid
                )
                switch status {
                case Relationship.statusAccepted: accepted.append(row)
                case Relationship.statusPending:  pendingLinked.append(row)
                default: break
                }
            } else {
                guard status == Relationship.statusPending else { continue }
                let display: String
                if let email = rel.patientEmail, !email.isEmpty {
                    display = email
                } else if let phoneNumber = rel.patientPhone, !phoneNumber.isEmpty {
                    display = phoneNumber
                } else {
                    display = "Unknown"
                }
                unlinked.append(UnlinkedPendingRequest(
                    id: relId,
                    displayName: display,
                    email: rel.patientEmail,
                    phone: rel.patientPhone,
                    relationshipObjectId: relId
                ))
            }
        }

        acceptedPatients = accepted
        pendingPatients  = pendingLinked
        pendingUnlinked  = unlinked
    }

    func fetchContacts() async {
        guard let store = AppDelegateKey.defaultValue?.store else { return }
        isLoadingContacts = true
        defer { isLoadingContacts = false }

        let query = OCKContactQuery(for: Date())
        let rawContacts = (try? await store.fetchContacts(query: query)) ?? []

        let acceptedEmails = Set(acceptedPatients.compactMap { $0.email?.lowercased() })
        let pendingEmails  = Set(pendingPatients.compactMap { $0.email?.lowercased() })
                                .union(Set(pendingUnlinked.compactMap { $0.email?.lowercased() }))

        contactItems = rawContacts.compactMap { contact in
            guard let email = contact.emailAddresses?.first?.value.lowercased(),
                  !email.isEmpty else { return nil }

            let phone = contact.phoneNumbers?.first?.value.lowercased()
            let name  = PersonNameComponentsFormatter()
                .string(from: contact.name)
                .trimmingCharacters(in: .whitespaces)

            let status: String?
            if acceptedEmails.contains(email) {
                status = Relationship.statusAccepted
            } else if pendingEmails.contains(email) {
                status = Relationship.statusPending
            } else {
                status = nil
            }

            let username = contact.userInfo?["parseUsername"]

            return ContactItem(
                id: contact.id,
                displayName: name.isEmpty ? contact.id : name,
                email: email,
                phone: phone,
                userObjectId: nil,          // not resolved — patient claims their own objectId
                username: username.flatMap { $0.isEmpty ? nil : $0 },
                connectionStatus: status
            )
        }
    }

    func sendConnectionRequest(to contact: ContactItem) async {
        guard let email = contact.email, !email.isEmpty else {
            errorMessage = "This contact has no email address. Only email-identified contacts can be invited."
            return
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let resolvedUsername: String?
        if let username = contact.username {
            resolvedUsername = username
        } else {
            resolvedUsername = (try? await Patient.query("email" == email).first())?.username
        }

        do {
            let currentUser = try await User.current()
            guard let myObjectId = currentUser.objectId,
                  let myUsername = currentUser.username else { return }

            let saved = try await Relationship.createRequest(
                clinicianObjectId: myObjectId,
                clinicianUsername: myUsername,
                patientUsername: resolvedUsername,
                patientEmail: email
            )

            guard saved != nil else { return }

            Logger.contact.info(
                "Connection request created for \(email, privacy: .private)"
            )

            await fetchPatients()
            await fetchContacts()
        } catch {
            Logger.contact.debug("sendConnectionRequest error: \(error)")
        }
    }

    func cancelRequest(row: PatientRow) async {
        await cancelRequest(relationshipObjectId: row.relationshipObjectId)
    }

    func cancelRequest(unlinked row: UnlinkedPendingRequest) async {
        await cancelRequest(relationshipObjectId: row.relationshipObjectId)
    }

    private func cancelRequest(relationshipObjectId: String) async {
        do {
            var rel = Relationship()
            rel.objectId = relationshipObjectId
            let fetched  = try await rel.fetch()
            var mutable  = fetched
            mutable.status = Relationship.statusRejected
            _ = try await mutable.save()
            await fetchPatients()
        } catch {
            errorMessage = "Could not cancel request: \(error.localizedDescription)"
        }
    }

    func resetContactSheet() {
        contactFilter = ""
        errorMessage  = nil
    }
}
