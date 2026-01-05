import Foundation

enum TransactionType: Int, Codable, CaseIterable, Hashable {
    case expense = 0
    case income = 1
}

struct Expense: Identifiable, Hashable {
    var id: Int
    var amount: Double
    var type: TransactionType = .expense    // デフォルトは支出
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
