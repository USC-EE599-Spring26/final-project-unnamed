//
//  MyContactViewController.swift
//  OCKSample
//
//  Created by Yu-Chieh on 2026/4/2.
//  Copyright © 2026 Network Reconnaissance Lab. All rights reserved.
//

import UIKit
import CareKitStore
import CareKitUI
import CareKit
import Contacts
import ContactsUI
import ParseSwift
import ParseCareKit
import os.log

class MyContactViewController: OCKListViewController {

	fileprivate var contacts = [OCKAnyContact]()
	fileprivate let store: OCKAnyStoreProtocol
	fileprivate let viewSynchronizer = OCKDetailedContactViewSynchronizer()

	/// Initialize using a store manager. All of the contacts in the store manager will be queried and dispalyed.
	///
	/// - Parameter store: The store from which to query the tasks.
	/// - Parameter viewSynchronizer: The type of view to show
	init(store: OCKAnyStoreProtocol
	) {
		self.store = store
		super.init(nibName: nil, bundle: nil)
	}

	@available(*, unavailable)
	public required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		Task {
			try? await fetchMyContact()
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		Task {
			try? await fetchMyContact()
		}
	}

	override func appendViewController(
		_ viewController: UIViewController,
		animated: Bool
	) {
		super.appendViewController(viewController, animated: animated)
		// Make sure this contact card matches app style when possible
		if let carekitView = viewController.view as? OCKView {
			carekitView.customStyle = CustomStylerKey.defaultValue
		}
	}

	func fetchMyContact() async throws {

		guard (try? await User.current()) != nil,
			  let personUUIDString = try? await Utility.getRemoteClockUUID().uuidString else {
			Logger.myContact.error("User not logged in")
			self.contacts.removeAll()
			return
		}

		/*
         TODOx: How would you modify this query to only fetch the contact that belongs to this device?

		 Hint 1: There are multiple ways to do this. You can modify the query
		 below which can work.

		 Hint2: Look at the other queries in the app related to the uuid of the
		 user/patient who's signed in.

		 Hint3: You should have a warning currently, solving this properly would
		 get rid of the warning without changing the line the warning is on.
		 */
		var query = OCKContactQuery(for: Date())
		query.sortDescriptors.append(.familyName(ascending: true))
		query.sortDescriptors.append(.givenName(ascending: true))

		self.contacts = try await store.fetchAnyContacts(query: query)
		self.displayContacts()
	}

	func displayContacts() {
		self.clear()
		for contact in self.contacts {
			var contactQuery = OCKContactQuery(for: Date())
			contactQuery.ids = [contact.id]
			contactQuery.limit = 1
			let contactViewController = OCKDetailedContactViewController(
				query: contactQuery,
				store: store,
				viewSynchronizer: viewSynchronizer
			)
			self.appendViewController(contactViewController, animated: false)
		}
	}
}
