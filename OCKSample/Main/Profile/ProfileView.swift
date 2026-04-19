//
//  ProfileView.swift
//  OCKSample
//
//  Created by Corey Baker on 11/24/20.
//  Copyright © 2020 Network Reconnaissance Lab. All rights reserved.
//

import CareKitUI
import CareKitStore
import CareKit
import os.log
import SwiftUI

struct ProfileView: View {
    @CareStoreFetchRequest(query: ProfileViewModel.queryPatient()) private var patients
    @CareStoreFetchRequest(query: ProfileViewModel.queryContacts()) private var contacts
    @StateObject private var viewModel = ProfileViewModel()
    @ObservedObject var loginViewModel: LoginViewModel

    // MARK: Navigation
    @State var isPresentingAddTask = false
    @State var isShowingSaveAlert = false
    @State var isPresentingContact = false
    @State var isPresentingImagePicker = false

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    #if os(iOS)
                    ProfileImageView(viewModel: viewModel)
                        .listRowBackground(Color.clear)
                    #endif
                    Section(header: Text("About")) {
                        TextField("First Name",
                                  text: $viewModel.firstName)
                        .padding()
                        .cornerRadius(20.0)
                        .shadow(radius: 10.0, x: 20, y: 10)

                        TextField("Last Name",
                                  text: $viewModel.lastName)
                        .padding()
                        .cornerRadius(20.0)
                        .shadow(radius: 10.0, x: 20, y: 10)

                        DatePicker("Birthday",
                                   selection: $viewModel.birthday,
                                   displayedComponents: [DatePickerComponents.date])
                        .padding()
                        .cornerRadius(20.0)
                        .shadow(radius: 10.0, x: 20, y: 10)
                    }
                    Section(header: Text("Contact")) {
                        TextField("Email Address", text: $viewModel.emailAddresses)
                        TextField("Message Number", text: $viewModel.messagingNumbers)
                        TextField("Phone Number", text: $viewModel.phoneNumbers)
                        TextField("Other Info", text: $viewModel.otherContactInfo)
                    }
                    Section(header: Text("Address")) {
                        TextField("Street", text: $viewModel.street)
                        TextField("City", text: $viewModel.city)
                        TextField("State", text: $viewModel.state)
                        TextField("Postal code", text: $viewModel.zipcode)
                    }
                    Section {
                        Button(action: {
                            Task {
                                await viewModel.saveProfile()
                            }
                        }, label: {
                            Text("Save Profile")
                                .font(.headline)
                                .foregroundColor(.green)
                                .padding(.vertical, 15)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(Color.white)
                                .cornerRadius(15)
                        })
                        .listRowBackground(Color.clear)

                        // Notice that "action" is a closure (which is essentially
                        // a function as argument like we discussed in class)
                        Button(action: {
                            Task {
                                await loginViewModel.logout()
                            }
                        }, label: {
                            Text("Log Out")
                                .font(.headline)
                                .foregroundColor(.red)
                                .padding(.vertical, 15)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(Color.white)
                                .cornerRadius(15)
                        })
                        .listRowBackground(Color.clear)
                    }
                    .listRowSeparator(.hidden)

                } // Form ends
            }
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("My Contact") {
                        viewModel.isPresentingContact = true
                    }
                    .sheet(isPresented: $viewModel.isPresentingContact) {
                        MyContactView()
                    }
                }
                #endif
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Task") {
                        isPresentingAddTask = true
                    }
                    .sheet(isPresented: $isPresentingAddTask) {
                        CareKitTaskView()
                    }
                }
            }

            #if os(iOS)
            .sheet(isPresented: $viewModel.isPresentingImagePicker) {
                ImagePicker(image: $viewModel.profileUIImage)
            }
            #endif
            .alert(isPresented: $viewModel.isShowingSaveAlert) {
                return Alert(title: Text("Update"),
                             message: Text(viewModel.alertMessage),
                             dismissButton: .default(Text("Ok"), action: {
                                viewModel.isShowingSaveAlert = false
                             }))
            }
        }
        .onReceive(patients.publisher) { publishedPatient in
            viewModel.updatePatient(publishedPatient.result)
        }

        .onReceive(contacts.publisher) { publishedContact in
            viewModel.updateContact(publishedContact.result)
        }

    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(loginViewModel: .init())
            .accentColor(Color.accentColor)
            .environment(\.careStore, Utility.createPreviewStore())
    }
}
