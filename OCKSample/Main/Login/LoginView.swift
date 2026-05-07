//
//  LoginView.swift
//  OCKSample
//
//  Created by Corey Baker on 10/29/20.
//  Copyright © 2020 Network Reconnaissance Lab. All rights reserved.
//

import ParseSwift
import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(\.tintColorFlip) var tintColorFlip
    @ObservedObject var viewModel: LoginViewModel

    @State var username = ""
    @State var password = ""
    @State var firstName = ""
    @State var lastName = ""
    @State var email = ""
    @State var signupLoginSegmentValue = 0
    @State var selectedRole: UserType = .patient

    var body: some View {
        VStack {
            Text("APP_NAME")
                .font(.largeTitle)
                .foregroundColor(.white)
                .padding()

            Image("exercise.jpg")
                .resizable()
                .frame(width: 150, height: 150, alignment: .center)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(.white), lineWidth: 4))
                .shadow(radius: 10)
                .padding()

            Picker(selection: $signupLoginSegmentValue, label: Text("LOGIN_PICKER")) {
                Text("LOGIN").tag(0)
                Text("SIGN_UP").tag(1)
            }
            .pickerStyle(.segmented)
            .background(Color(tintColorFlip))
            .cornerRadius(20.0)
            .padding()

            VStack(alignment: .leading) {
                TextField(
                    signupLoginSegmentValue == 1 ? "USERNAME" : "USERNAME_OR_EMAIL",
                    text: $username
                )
                .padding()
                .background(.white)
                .cornerRadius(20.0)
                .shadow(radius: 10.0, x: 20, y: 10)

                SecureField("PASSWORD", text: $password)
                    .padding()
                    .background(.white)
                    .cornerRadius(20.0)
                    .shadow(radius: 10.0, x: 20, y: 10)

                if signupLoginSegmentValue == 1 {
                    TextField("EMAIL", text: $email)
                        .padding()
                        .background(.white)
                        .cornerRadius(20.0)
                        .shadow(radius: 10.0, x: 20, y: 10)

                    TextField("GIVEN_NAME", text: $firstName)
                        .padding()
                        .background(.white)
                        .cornerRadius(20.0)
                        .shadow(radius: 10.0, x: 20, y: 10)

                    TextField("FAMILY_NAME", text: $lastName)
                        .padding()
                        .background(.white)
                        .cornerRadius(20.0)
                        .shadow(radius: 10.0, x: 20, y: 10)

                    HStack(spacing: 16) {
                        ForEach([UserType.patient, UserType.clinician]) { role in
                            Button {
                                selectedRole = role
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: role.systemImage)
                                        .font(.title2)
                                    Text(role.displayName)
                                        .font(.subheadline).bold()
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(
                                    selectedRole == role
                                        ? Color.white
                                        : Color.white.opacity(0.2)
                                )
                                .foregroundColor(
                                    selectedRole == role
                                        ? Color.accentColor
                                        : Color.white
                                )
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.white, lineWidth: selectedRole == role ? 2 : 0)
                                )
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding()

            Button {
                switch signupLoginSegmentValue {
                case 1:
                    Task {
                        await viewModel.signup(
                            selectedRole,
                            username: username,
                            password: password,
                            firstName: firstName,
                            lastName: lastName,
                            email: email
                        )
                    }
                default:
                    Task {
                        await viewModel.login(
                            usernameOrEmail: username,
                            password: password
                        )
                    }
                }
            } label: {
                Text(signupLoginSegmentValue == 1 ? "SIGN_UP" : "LOGIN")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(width: 300)
            }
            .background(Color(.green))
            .cornerRadius(15)

            if signupLoginSegmentValue == 0 {
                Button {
                    Task { await viewModel.loginAnonymously() }
                } label: {
                    Text("LOGIN_ANONYMOUSLY")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(width: 300)
                }
                .background(Color(.lightGray))
                .cornerRadius(15)
            }

            if let error = viewModel.loginError {
                Text("\(String(localized: "ERROR")): \(error.message)")
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color(tintColorFlip), Color.accentColor]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView(viewModel: .init())
    }
}
