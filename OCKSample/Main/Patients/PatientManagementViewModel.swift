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

    // MARK: - Display model

    /// Linked patient row — always has a real `_User.objectId` and `username`.
    /// Used for accepted patients and for pending-but-already-linked patients.
    struct PatientRow: Identifiable {
        let id: String                      // Relationship.objectId
        let username: String                // non-optional — row is linked
        let displayName: String
        let email: String?
        let phoneNumber: String?
        let status: String                  // Relationship.status
        let relationshipObjectId: String
        let patientObjectId: String         // non-optional — row is linked
    }

    /// Pending request that has not yet been linked to a real user.
    /// The clinician sent it using only an email or phone, and the target
    /// hasn't signed up (or hasn't logged in since signing up). Once they
    /// log in, `Relationship.linkPendingForCurrentUser()` claims the row
    /// and it will appear as a linked PatientRow on the next fetch.
    struct UnlinkedPendingRequest: Identifiable {
        let id: String                      // Relationship.objectId
        let displayName: String             // email or phone — whatever was used
        let email: String?
        let phone: String?
        let relationshipObjectId: String
    }

    // MARK: - Contact wrapper for AddPatientSheet

    struct ContactItem: Identifiable {
        let id: String                      // OCKAnyContact.id
        let displayName: String
        let email: String?
        let phone: String?
        /// Parse _User.objectId — read from OCKContact.userInfo at load time
        let userObjectId: String?
        /// Parse username — read from OCKContact.userInfo at load time
        let username: String?
        /// nil = not connected yet; "pending" or "accepted" = already in Relationship table
        var connectionStatus: String?
    }

    // MARK: - Published — patient list

    @Published var acceptedPatients: [PatientRow] = []
    @Published var pendingPatients: [PatientRow] = []
    @Published var pendingUnlinked: [UnlinkedPendingRequest] = []
    @Published var isLoading   = false
    @Published var errorMessage: String?

    // MARK: - Published — contact picker (AddPatientSheet)

    @Published var contactItems: [ContactItem] = []
    @Published var contactFilter    = ""
    @Published var isLoadingContacts = false
    @Published var isSending        = false

    // MARK: - Filtered contacts (local text filter)

    var filteredContacts: [ContactItem] {
        guard !contactFilter.isEmpty else { return contactItems }
        let lower = contactFilter.lowercased()
        return contactItems.filter { item in
            item.displayName.lowercased().contains(lower)
            || (item.email?.lowercased().contains(lower) ?? false)
            || (item.phone?.lowercased().contains(lower) ?? false)
        }
    }

    // MARK: - Fetch linked patients (Relationship table)

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
                // Safe to force-unwrap given the guard above
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
                // Unlinked — only meaningful while pending. Skip rejected/accepted
                // unlinked rows (shouldn't normally happen).
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

    // MARK: - Load contacts from clinician's own CareKit store

    func fetchContacts() async {
        guard let store = AppDelegateKey.defaultValue?.store else { return }
        isLoadingContacts = true
        defer { isLoadingContacts = false }

        let query = OCKContactQuery(for: Date())
        let rawContacts = (try? await store.fetchContacts(query: query)) ?? []

        // Match status by email only — phone is not used as an identifier.
        let acceptedEmails = Set(acceptedPatients.compactMap { $0.email?.lowercased() })
        let pendingEmails  = Set(pendingPatients.compactMap { $0.email?.lowercased() })
                                .union(Set(pendingUnlinked.compactMap { $0.email?.lowercased() }))

        // Only include contacts that have an email address (required for inviting).
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

    // MARK: - Send connection request from a contact

    func sendConnectionRequest(to contact: ContactItem) async {
        // Users are identified by email only — contacts without email cannot be invited.
        guard let email = contact.email, !email.isEmpty else {
            errorMessage = "This contact has no email address. Only email-identified contacts can be invited."
            return
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        // Optional username hint from OCKContact.userInfo or the Patient table.
        // Used for display only — the patient claims their own objectId when
        // they call acceptRequest(), so we never need to resolve patientObjectId here.
        // Note: ?? cannot be used here because its rhs would need await (not async-aware).
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

            // nil → duplicate pending row, already logged inside createRequest.
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

    // MARK: - Cancel pending request (clinician side)

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

    // MARK: - Helpers

    func resetContactSheet() {
        contactFilter = ""
        errorMessage  = nil
    }
}
