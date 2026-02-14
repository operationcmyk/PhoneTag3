//
//  PhoneTag3App.swift
//  PhoneTag3
//
//  Created by chris langer on 2/13/26.
//

import SwiftUI

@main
struct PhoneTag3App: App {
    @StateObject var session = SessionManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
        }
    }
}


