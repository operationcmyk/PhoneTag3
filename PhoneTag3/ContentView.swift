//
//  ContentView.swift
//  PhoneTag3
//
//  Created by chris langer on 2/13/26.
//

import SwiftUI
import UIKit


struct ContentView: View {
    @EnvironmentObject var session: SessionManager
    
    var body: some View {
        ZStack{
            mainBackground()
            if(session.isLoggedIn){
                HomeView()
                    .zIndex(1)
                    .transition(.asymmetric(
                                      insertion: .move(edge: .trailing).combined(with: .opacity),
                                      removal: .move(edge: .leading).combined(with: .opacity)
                                  ))
                                  .id("home")               }else{
                SignInView()
                                          .zIndex(1)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
                    .id("login")

            }

        }
    }
}

struct mainBackground: View{
    var body: some View{
        VStack{
            Image("arsenalblue")
                .resizable()
                .frame(maxWidth:.infinity, maxHeight:.infinity)
                .edgesIgnoringSafeArea(.all)
        }
    }
}



struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
        .environmentObject(SessionManager())
    }
}
