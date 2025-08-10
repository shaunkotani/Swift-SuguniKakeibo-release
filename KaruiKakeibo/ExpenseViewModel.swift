//
//  ExpenseViewModel.swift (修正版)
//  Suguni-Kakeibo-2
//
//  Created by 大谷駿介 on 2025/07/31.
//

import Foundation

@MainActor
class ExpenseViewModel: ObservableObject {
    @Published var expenses: [Expense] = []
    @Published var categories: [(id: Int, name: String)] = []
    @Published var fullCategories: [FullCategory] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // データ操作中フラグ
    private var isOperating = false
    
    // 削除済みカテゴリのキャッシュ
    private var deletedCategoriesCache: [Int: FullCategory] = [:]
    
    init() {
        // 同期的に初期化
        loadInitialData()
    }
    
    // MARK: - 初期データロード
    private func loadInitialData() {
        self.fullCategories = ExpenseDatabaseManager.shared.fetchFullCategories()
        self.categories = self.fullCategories.map { (id: $0.id, name: $0.name) }
        self.expenses = ExpenseDatabaseManager.shared.fetchExpenses()
        
        // 削除済みカテゴリのキャッシュを構築
        buildDeletedCategoriesCache()
        
        print("📊 初期データロード完了: カテゴリ\(categories.count)件, 支出\(expenses.count)件")
    }
    
    private func buildDeletedCategoriesCache() {
        // 支出で使用されているがアクティブでないカテゴリIDを特定
        let usedCategoryIds = Set(expenses.map { $0.categoryId })
        let activeCategoryIds = Set(fullCategories.map { $0.id })
        let deletedCategoryIds = usedCategoryIds.subtracting(activeCategoryIds)
        
        // 削除済みカテゴリの情報をキャッシュ
        for deletedId in deletedCategoryIds {
            deletedCategoriesCache[deletedId] = FullCategory(
                id: deletedId,
                name: "削除済みカテゴリ",
                icon: "trash.circle",
                color: "gray",
                isDefault: false,
                isVisible: false,
                isActive: false,
                sortOrder: 999
            )
        }
    }

    // MARK: - データ取得
    func fetchExpenses() {
        guard !isOperating else { return }
        
        Task {
            await performDataOperation {
                let fetchedExpenses = ExpenseDatabaseManager.shared.fetchExpenses()
                await MainActor.run {
                    self.expenses = fetchedExpenses
                    self.errorMessage = nil
                    self.buildDeletedCategoriesCache()
                }
            }
        }
    }

    func fetchCategories() {
        guard !isOperating else { return }
        
        Task {
            await performDataOperation {
                let fetchedFullCategories = ExpenseDatabaseManager.shared.fetchFullCategories()
                let fetchedCategories = fetchedFullCategories.map { (id: $0.id, name: $0.name) }
                await MainActor.run {
                    self.fullCategories = fetchedFullCategories
                    self.categories = fetchedCategories
                    self.errorMessage = nil
                    self.buildDeletedCategoriesCache()
                }
            }
        }
    }
    
    // MARK: - カテゴリ管理機能
    
    func getVisibleCategories() -> [(id: Int, name: String)] {
        return fullCategories.filter { $0.isVisible }.map { (id: $0.id, name: $0.name) }
    }
    
    func getAllCategoriesIncludingDeleted() -> [FullCategory] {
        var allCategories = fullCategories
        
        // 削除済みカテゴリも含める（使用中の場合のみ）
        for (deletedId, deletedCategory) in deletedCategoriesCache {
            if !allCategories.contains(where: { $0.id == deletedId }) {
                allCategories.append(deletedCategory)
            }
        }
        
        return allCategories.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    func addCategory(_ category: FullCategory) {
        guard !isOperating else {
            self.errorMessage = "データ処理中です。しばらくお待ちください。"
            return
        }
        
        Task {
            await performDataOperation {
                ExpenseDatabaseManager.shared.insertCategory(category)
                
                let updatedFullCategories = ExpenseDatabaseManager.shared.fetchFullCategories()
                let updatedCategories = updatedFullCategories.map { (id: $0.id, name: $0.name) }
                
                await MainActor.run {
                    self.fullCategories = updatedFullCategories
                    self.categories = updatedCategories
                    self.errorMessage = nil
                    print("✅ カテゴリを正常に追加しました: \(category.name)")
                }
            }
        }
    }
    
    func updateCategory(_ category: FullCategory) {
        guard !isOperating else {
            self.errorMessage = "データ処理中です。しばらくお待ちください。"
            return
        }
        
        Task {
            await performDataOperation {
                ExpenseDatabaseManager.shared.updateCategory(category)
                
                let updatedFullCategories = ExpenseDatabaseManager.shared.fetchFullCategories()
                let updatedCategories = updatedFullCategories.map { (id: $0.id, name: $0.name) }
                
                await MainActor.run {
                    self.fullCategories = updatedFullCategories
                    self.categories = updatedCategories
                    self.errorMessage = nil
                    print("✅ カテゴリを正常に更新しました: ID=\(category.id)")
                }
            }
        }
    }
    
    func updateCategoriesOrder(_ updatedCategories: [FullCategory]) {
        guard !isOperating else {
            self.errorMessage = "データ処理中です。しばらくお待ちください。"
            return
        }
        
        // 楽観的更新
        self.fullCategories = updatedCategories
        self.categories = updatedCategories.map { (id: $0.id, name: $0.name) }
        
        Task {
            await performDataOperation {
                ExpenseDatabaseManager.shared.updateCategoriesOrder(updatedCategories)
                
                await MainActor.run {
                    self.errorMessage = nil
                    print("✅ カテゴリ順序を正常に更新しました")
                }
            }
        }
    }
    
    func deleteCategory(id: Int) {
        guard !isOperating else {
            self.errorMessage = "データ処理中です。しばらくお待ちください。"
            return
        }
        
        // デフォルトカテゴリの削除をチェック
        if let category = fullCategories.first(where: { $0.id == id }), category.isDefault {
            self.errorMessage = "デフォルトカテゴリは削除できません。"
            return
        }
        
        Task {
            await performDataOperation {
                ExpenseDatabaseManager.shared.deleteCategoryLogically(id: id)
                
                let updatedFullCategories = ExpenseDatabaseManager.shared.fetchFullCategories()
                let updatedCategories = updatedFullCategories.map { (id: $0.id, name: $0.name) }
                
                await MainActor.run {
                    self.fullCategories = updatedFullCategories
                    self.categories = updatedCategories
                    self.errorMessage = nil
                    self.buildDeletedCategoriesCache() // キャッシュを再構築
                    print("✅ カテゴリを正常に削除しました: ID=\(id)")
                }
            }
        }
    }
    
    // MARK: - デフォルトカテゴリリセット機能
    func resetDefaultCategories() {
        guard !isOperating else {
            self.errorMessage = "データ処理中です。しばらくお待ちください。"
            return
        }
        
        Task {
            await performDataOperation {
                ExpenseDatabaseManager.shared.resetDefaultCategories()
                
                let updatedFullCategories = ExpenseDatabaseManager.shared.fetchFullCategories()
                let updatedCategories = updatedFullCategories.map { (id: $0.id, name: $0.name) }
                
                await MainActor.run {
                    self.fullCategories = updatedFullCategories
                    self.categories = updatedCategories
                    self.errorMessage = nil
                    self.buildDeletedCategoriesCache()
                    print("✅ デフォルトカテゴリをリセットしました")
                }
            }
        }
    }
    
    func getCategoryInfo(for id: Int) -> FullCategory? {
        // アクティブなカテゴリから検索
        if let category = fullCategories.first(where: { $0.id == id }) {
            return category
        }
        
        // 削除済みカテゴリから検索
        return deletedCategoriesCache[id]
    }
    
    // MARK: - 既存のデータ操作メソッド
    
    func addExpense(_ expense: Expense) {
        guard !isOperating else {
            self.errorMessage = "データ処理中です。しばらくお待ちください。"
            return
        }
        
        Task {
            await performDataOperation {
                ExpenseDatabaseManager.shared.insertExpense(expense: expense)
                
                let updatedExpenses = ExpenseDatabaseManager.shared.fetchExpenses()
                
                await MainActor.run {
                    self.expenses = updatedExpenses
                    self.errorMessage = nil
                    print("✅ 支出を正常に追加しました: ID=\(expense.id)")
                }
            }
        }
    }

    func updateExpense(_ expense: Expense) {
        guard !isOperating else {
            self.errorMessage = "データ処理中です。しばらくお待ちください。"
            return
        }
        
        Task {
            await performDataOperation {
                ExpenseDatabaseManager.shared.updateExpense(expense: expense)
                
                let updatedExpenses = ExpenseDatabaseManager.shared.fetchExpenses()
                
                await MainActor.run {
                    self.expenses = updatedExpenses
                    self.errorMessage = nil
                    print("✅ 支出を正常に更新しました: ID=\(expense.id)")
                }
            }
        }
    }

    func deleteExpense(id: Int) {
        guard !isOperating else {
            self.errorMessage = "データ処理中です。しばらくお待ちください。"
            return
        }
        
        // 楽観的更新: UIを即座に更新
        expenses.removeAll { $0.id == id }
        
        Task {
            await performDataOperation {
                ExpenseDatabaseManager.shared.deleteExpense(id: id)
                
                await MainActor.run {
                    self.errorMessage = nil
                    print("✅ 支出を正常に削除しました: ID=\(id)")
                }
            }
        }
    }
    
    // MARK: - バルク操作（複数削除用）
    func deleteExpenses(ids: [Int]) {
        guard !isOperating else {
            self.errorMessage = "データ処理中です。しばらくお待ちください。"
            return
        }
        
        // 楽観的更新
        expenses.removeAll { ids.contains($0.id) }
        
        Task {
            await performDataOperation {
                for id in ids {
                    ExpenseDatabaseManager.shared.deleteExpense(id: id)
                }
                
                await MainActor.run {
                    self.errorMessage = nil
                    print("✅ \(ids.count)件の支出を正常に削除しました")
                }
            }
        }
    }
    
    // MARK: - データ同期
    func refreshAllData() {
        guard !isOperating else { return }
        
        Task {
            await performDataOperation {
                let fetchedFullCategories = ExpenseDatabaseManager.shared.fetchFullCategories()
                let fetchedCategories = fetchedFullCategories.map { (id: $0.id, name: $0.name) }
                let fetchedExpenses = ExpenseDatabaseManager.shared.fetchExpenses()
                
                await MainActor.run {
                    self.fullCategories = fetchedFullCategories
                    self.categories = fetchedCategories
                    self.expenses = fetchedExpenses
                    self.errorMessage = nil
                    self.buildDeletedCategoriesCache()
                    print("✅ 全データを同期しました")
                }
            }
        }
    }
    
    // MARK: - ユーティリティメソッド
    func clearError() {
        errorMessage = nil
    }
    
    // 特定のカテゴリの支出を取得
    func expensesForCategory(_ categoryId: Int) -> [Expense] {
        return expenses.filter { $0.categoryId == categoryId }
    }
    
    // 特定の日付の支出を取得
    func expensesForDate(_ date: Date) -> [Expense] {
        let calendar = Calendar.current
        return expenses.filter { calendar.isDate($0.date, inSameDayAs: date) }
    }
    
    // 月別の支出を取得
    func expensesForMonth(_ month: Date) -> [Expense] {
        let calendar = Calendar.current
        let targetMonth = calendar.component(.month, from: month)
        let targetYear = calendar.component(.year, from: month)
        
        return expenses.filter { expense in
            let expenseMonth = calendar.component(.month, from: expense.date)
            let expenseYear = calendar.component(.year, from: expense.date)
            return expenseMonth == targetMonth && expenseYear == targetYear
        }
    }
    
    // カテゴリ名を取得（削除済み対応）
    func categoryName(for id: Int) -> String {
        // アクティブなカテゴリから検索
        if let category = categories.first(where: { $0.id == id }) {
            return category.name
        }
        
        // 削除済みカテゴリから検索
        if let deletedCategory = deletedCategoriesCache[id] {
            return deletedCategory.name
        }
        
        return "不明なカテゴリ"
    }
    
    // カテゴリアイコンを取得（削除済み対応）
    func categoryIcon(for id: Int) -> String {
        // アクティブなカテゴリから検索
        if let category = fullCategories.first(where: { $0.id == id }) {
            return category.icon
        }
        
        // 削除済みカテゴリから検索
        if let deletedCategory = deletedCategoriesCache[id] {
            return deletedCategory.icon
        }
        
        return "questionmark.circle" // 不明なカテゴリのアイコン
    }
    
    // カテゴリカラーを取得（削除済み対応）
    func categoryColor(for id: Int) -> String {
        // アクティブなカテゴリから検索
        if let category = fullCategories.first(where: { $0.id == id }) {
            return category.color
        }
        
        // 削除済みカテゴリから検索
        if let deletedCategory = deletedCategoriesCache[id] {
            return deletedCategory.color
        }
        
        return "gray" // 不明なカテゴリの色
    }
    
    // カテゴリが削除済みかチェック
    func isCategoryDeleted(id: Int) -> Bool {
        return deletedCategoriesCache.keys.contains(id)
    }
    
    // 削除済みカテゴリの使用統計
    func getDeletedCategoryUsage() -> [(categoryId: Int, categoryName: String, usageCount: Int)] {
        var usage: [(categoryId: Int, categoryName: String, usageCount: Int)] = []
        
        for (deletedId, deletedCategory) in deletedCategoriesCache {
            let count = expenses.filter { $0.categoryId == deletedId }.count
            if count > 0 {
                usage.append((categoryId: deletedId, categoryName: deletedCategory.name, usageCount: count))
            }
        }
        
        return usage.sorted { $0.usageCount > $1.usageCount }
    }
    
    // MARK: - プライベートヘルパー
    private func performDataOperation(_ operation: @escaping () async -> Void) async {
        await MainActor.run {
            self.isOperating = true
            self.isLoading = true
        }
        
        // 操作実行
        await operation()
        
        await MainActor.run {
            self.isOperating = false
            self.isLoading = false
        }
    }
}

// MARK: - エラー処理用拡張
// カテゴリ管理機能の最終確認用コード
extension ExpenseViewModel {
    // viewModel が正しくカテゴリ情報を返すかの確認
    func debugCategoryInfo() {
        print("=== カテゴリデバッグ情報 ===")
        print("アクティブカテゴリ数: \(fullCategories.count)")
        print("可視カテゴリ数: \(getVisibleCategories().count)")
        
        for category in fullCategories {
            print("ID: \(category.id), 名前: \(category.name), アイコン: \(category.icon), 色: \(category.color), 表示: \(category.isVisible), デフォルト: \(category.isDefault)")
        }
        
        let deletedUsage = getDeletedCategoryUsage()
        if !deletedUsage.isEmpty {
            print("削除済みカテゴリ使用状況:")
            for usage in deletedUsage {
                print("- ID: \(usage.categoryId), 名前: \(usage.categoryName), 使用回数: \(usage.usageCount)")
            }
        }
        print("========================")
    }
}
