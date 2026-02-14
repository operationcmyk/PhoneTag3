//
//  SignInView.swift
//  PhoneTag3
//
//  Created by chris langer on 2/14/26.
//

import SwiftUI
struct SignInView: View{
    @EnvironmentObject var session: SessionManager
    var isFormValid: Bool {
        !session.username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !session.password.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View{
        VStack{
            Image("loginLogo")
            
            ZStack{
                GeometryReader { geometry in
                    Image("loginFields")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 0.9)
                    // center it inside the GeometryReader
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                .frame(height: 220)
                GeometryReader { geometry in
                VStack {
                    TextField("Username", text: $session.username)
                        .font(.custom("BadaBoom BB",size:24))
                        .padding()
                        .frame(width: geometry.size.width * 0.8)
                        .position(x: geometry.size.width / 2, y:geometry.size.height * 0.35)
                    SecureField("Password", text: $session.password)
                        .font(.custom("BadaBoom BB",size:24))
                        .padding()
                        .frame(width: geometry.size.width * 0.8)
                        .position(x: geometry.size.width / 2, y:geometry.size.height * 0.14)
                }
                }
                .frame(height: 220)
                    
            
            }
            GeometryReader { geometry in
                    Button(action: {
                        print("Login tapped")
                        withAnimation(.easeInOut(duration: 0.35)) {
                               session.isLoggedIn = true
                           }
                    }) {
                    Image("loginButton")
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 0.5)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
              
            }
            .buttonStyle(.plain)
            .scaleEffect(1.0)
            .disabled(!isFormValid)
            }
            .frame(height: 100)
        }
        
    }
}

struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView()
            .environmentObject(SessionManager())
    }
}
