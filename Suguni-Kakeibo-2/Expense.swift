//
//  Expense.swift
//  Suguni-Kakeibo-2
//
//  Created by 大谷駿介 on 2025/07/29.
//

import Foundation

struct Expense: Identifiable, Hashable {
    var id: Int
    var amount: Double
    var date: Date
    var note: String
    var categoryId: Int
    var userId: Int
    
    // Hashableプロトコルのためのhash(into:)メソッド
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatableプロトコルのための==演算子
    static func == (lhs: Expense, rhs: Expense) -> Bool {
        return lhs.id == rhs.id
    }
}
