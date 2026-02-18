//
//  HomeView.swift
//  PhoneTag3
//
//  Created by chris langer on 2/14/26.
//

import SwiftUI

struct HomeViewTest: View {
    @EnvironmentObject var session: SessionManager
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
        Button("Logout"){
            session.isLoggedIn = false
            session.password = ""
            
        }
    }
}

struct HomeViewTest_Previews: PreviewProvider {
    static var previews: some View {
        HomeViewTest()
    }
}
