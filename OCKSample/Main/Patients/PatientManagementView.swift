//
//  PatientManagementView.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import SwiftUI

struct PatientManagementView: View {

    @StateObject private var viewModel = PatientManagementViewModel()
    @State private var showingContactPicker = false

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading
                    && viewModel.acceptedPatients.isEmpty
                    && viewModel.pendingPatients.isEmpty
                    && viewModel.pendingUnlinked.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.acceptedPatients.isEmpty
                            && viewModel.pendingPatients.isEmpty
                            && viewModel.pendingUnlinked.isEmpty {
                    ContentUnavailableView(
                        "No Connections",
                        systemImage: "person.2.slash",
                        description: Text(
                            "Tap + to send a connection request to one of your contacts."
                        )
                    )
                } else {
                    patientList
                }
            }
            .navigationTitle("Patients")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingContactPicker = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .sheet(isPresented: $showingContactPicker, onDismiss: {
                viewModel.resetContactSheet()
            }) {
                ContactPickerSheet(viewModel: viewModel, isPresented: $showingContactPicker)
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task { await viewModel.fetchPatients() }
        }
    }

    // MARK: - Patient list

    private var patientList: some View {
        List {
            // ── Accepted connections ───────────────────────────────────
            if !viewModel.acceptedPatients.isEmpty {
                Section("Connected Patients") {
                    ForEach(viewModel.acceptedPatients) { row in
                        NavigationLink {
                            PatientDetailView(patient: row)
                        } label: {
                            PatientRowView(row: row)
                        }
                    }
                }
            }

            // ── Pending outgoing requests (linked) ─────────────────────
            if !viewModel.pendingPatients.isEmpty {
                Section("Pending Requests") {
                    ForEach(viewModel.pendingPatients) { row in
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle")
                                .font(.title)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.displayName).font(.headline)
                                Text("Awaiting patient acceptance")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await viewModel.cancelRequest(row: row) }
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // ── Unlinked pending (target hasn't signed up yet) ─────────
            if !viewModel.pendingUnlinked.isEmpty {
                Section {
                    ForEach(viewModel.pendingUnlinked) { row in
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.badge")
                                .font(.title)
                                .foregroundStyle(.gray)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.displayName).font(.headline)
                                Text("Waiting for sign-up")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                Task { await viewModel.cancelRequest(unlinked: row) }
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Awaiting Sign-up")
                } footer: {
                    Text(
                        "These contacts haven't created an account yet. " +
                        "The request will activate automatically when they sign up."
                    )
                }
            }
        }
    }
}

// MARK: - Patient row

private struct PatientRowView: View {
    let row: PatientManagementViewModel.PatientRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName).font(.headline)
                if let email = row.email {
                    Label(email, systemImage: "envelope")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let phone = row.phoneNumber {
                    Label(phone, systemImage: "phone")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(row.username)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Contact picker sheet

struct ContactPickerSheet: View {

    @ObservedObject var viewModel: PatientManagementViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoadingContacts {
                    ProgressView("Loading contacts…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.contactItems.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.slash",
                        description: Text(
                            "You have no contacts in your contact list."
                        )
                    )
                } else if viewModel.filteredContacts.isEmpty {
                    ContentUnavailableView.search
                } else {
                    contactList
                }
            }
            .navigationTitle("Add Patient")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.contactFilter, prompt: "Search contacts")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task { await viewModel.fetchContacts() }
    }

    private var contactList: some View {
        List(viewModel.filteredContacts) { contact in
            ContactRow(
                contact: contact,
                isSending: viewModel.isSending
            ) {
                Task { await viewModel.sendConnectionRequest(to: contact) }
            }
        }
    }
}

// MARK: - Contact row

private struct ContactRow: View {

    let contact: PatientManagementViewModel.ContactItem
    let isSending: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.title)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName).font(.headline)
                if let email = contact.email {
                    Label(email, systemImage: "envelope")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let phone = contact.phone {
                    Label(phone, systemImage: "phone")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusView
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch contact.connectionStatus {
        case Relationship.statusAccepted:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

        case Relationship.statusPending:
            Label("Pending", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.orange)

        default:
            Button(action: onConnect) {
                if isSending {
                    ProgressView()
                } else {
                    Label("Connect", systemImage: "person.badge.plus")
                        .font(.caption)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isSending)
        }
    }

    private var iconColor: Color {
        switch contact.connectionStatus {
        case Relationship.statusAccepted: return .green
        case Relationship.statusPending:  return .orange
        default: return .blue
        }
    }
}
