//
//  NotificationView.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/23.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import SwiftUI

struct NotificationView: View {

    @StateObject private var viewModel = NotificationViewModel()

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading && viewModel.notifications.isEmpty {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.notifications.isEmpty {
                    ContentUnavailableView(
                        "No Notifications",
                        systemImage: "bell.slash",
                        description: Text("You have no notifications right now.")
                    )
                } else {
                    notificationList
                }
            }
            .navigationTitle("Notifications")
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task { await viewModel.fetchNotifications() }
        }
    }

    private var notificationList: some View {
        List(viewModel.notifications) { item in
            NotificationRow(item: item) {
                Task { await viewModel.accept(item) }
            } onReject: {
                Task { await viewModel.reject(item) }
            }
        }
    }
}

// MARK: - Notification row

private struct NotificationRow: View {
    let item: NotificationViewModel.NotificationItem
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.message)
                        .font(.subheadline)
                        .fontWeight(item.isRead ? .regular : .semibold)
                    if let date = item.createdAt {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if item.isRead {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            if !item.isRead {
                HStack(spacing: 12) {
                    Button(action: onAccept) {
                        Label("Accept", systemImage: "checkmark")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(role: .destructive, action: onReject) {
                        Label("Decline", systemImage: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(item.isRead ? 0.6 : 1.0)
    }

    private var iconName: String {
        switch item.type {
        case AppNotification.typeConnectionRequest:  return "person.badge.plus"
        case AppNotification.typeCarePlanAssignment: return "list.clipboard"
        default: return "bell"
        }
    }

    private var iconColor: Color {
        switch item.type {
        case AppNotification.typeConnectionRequest:  return .blue
        case AppNotification.typeCarePlanAssignment: return .green
        default: return .secondary
        }
    }
}
