//
//  sessionManageer.swift
//  PhoneTag3
//
//  Created by chris langer on 2/14/26.
//

import Foundation


class SessionManager: ObservableObject{
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var currentArsenal: [ArsenalItem] = []
    @Published var isLoggedIn: Bool = false
}


struct Weapon{
    var name: String = ""
    var desc: String = ""
}

struct ArsenalItem{
   var Weapon: String = ""
   var count: Int = 0
}



