//
//  ExpenseDatabaseManager.swift (修正版)
//  Suguni-Kakeibo-2
//
//  Created by 大谷駿介 on 2025/07/29.
//

import Foundation
import SQLite3

class ExpenseDatabaseManager {
    static let shared = ExpenseDatabaseManager()
    private var db: OpaquePointer?

    deinit {
        closeDatabase()
    }

    private init() {
        openDatabase()
        createTable()
    }

    func beginTransaction() {
        guard db != nil else { return }
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
    }

    func commitTransaction() {
        guard db != nil else { return }
        sqlite3_exec(db, "COMMIT TRANSACTION", nil, nil, nil)
    }

    func rollbackTransaction() {
        guard db != nil else { return }
        sqlite3_exec(db, "ROLLBACK TRANSACTION", nil, nil, nil)
    }

    private func openDatabase() {
        let fileURL = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("expenses.sqlite")

        if sqlite3_open(fileURL.path, &db) != SQLITE_OK {
            print("Error opening database")
            db = nil
        } else {
            print("✅ データベース接続成功: \(fileURL.path)")
        }
    }

    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    private func createTable() {
        guard db != nil else {
            print("Database is not available.")
            return
        }
        
        let createExpenseTableString = """
        CREATE TABLE IF NOT EXISTS Expense(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL,
        date TEXT,
        note TEXT,
        categoryId INTEGER,
        userId INTEGER);
        """
        var createStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, createExpenseTableString, -1, &createStatement, nil) == SQLITE_OK {
            sqlite3_step(createStatement)
        }
        sqlite3_finalize(createStatement)

        // 拡張されたCategoryテーブル
        let createCategoryTableString = """
        CREATE TABLE IF NOT EXISTS Category(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        icon TEXT DEFAULT 'tag.fill',
        color TEXT DEFAULT 'gray',
        isDefault INTEGER DEFAULT 0,
        isVisible INTEGER DEFAULT 1,
        isActive INTEGER DEFAULT 1,
        sortOrder INTEGER DEFAULT 0,
        createdAt TEXT DEFAULT '');
        """
        if sqlite3_prepare_v2(db, createCategoryTableString, -1, &createStatement, nil) == SQLITE_OK {
            sqlite3_step(createStatement)
        }
        sqlite3_finalize(createStatement)

        // 既存テーブルに新しいカラムを追加（マイグレーション）
        migrateDatabase()
        
        insertDefaultCategories()
    }
    
    // MARK: - 修正1: migrateDatabase()メソッド内のインデックス作成部分
    private func migrateDatabase() {
        guard db != nil else { return }
        
        print("🔧 データベースマイグレーション開始")
        
        // カラムの存在確認用ヘルパー関数
        func columnExists(_ columnName: String, in tableName: String) -> Bool {
            let pragmaQuery = "PRAGMA table_info(\(tableName));"
            var statement: OpaquePointer?
            var exists = false
            
            if sqlite3_prepare_v2(db, pragmaQuery, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let namePtr = sqlite3_column_text(statement, 1) {
                        let name = String(cString: namePtr)
                        if name == columnName {
                            exists = true
                            break
                        }
                    }
                }
            }
            sqlite3_finalize(statement)
            return exists
        }
        
        // 必要なカラムを個別にチェックして追加
        let columnsToAdd = [
            ("icon", "TEXT DEFAULT 'tag.fill'"),
            ("color", "TEXT DEFAULT 'gray'"),
            ("isDefault", "INTEGER DEFAULT 0"),
            ("isVisible", "INTEGER DEFAULT 1"),
            ("isActive", "INTEGER DEFAULT 1"),
            ("sortOrder", "INTEGER DEFAULT 0"),
            ("createdAt", "TEXT DEFAULT ''")
        ]
        
        for (columnName, columnDefinition) in columnsToAdd {
            if !columnExists(columnName, in: "Category") {
                let alterSQL = "ALTER TABLE Category ADD COLUMN \(columnName) \(columnDefinition);"
                let result = sqlite3_exec(db, alterSQL, nil, nil, nil)
                if result == SQLITE_OK {
                    print("✅ カラム追加成功: \(columnName)")
                } else {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    print("❌ カラム追加失敗: \(columnName) - \(errorMessage)")
                }
            } else {
                print("⚪ カラム既存: \(columnName)")
            }
        }
        
        // 🔥 修正：UNIQUEインデックスを修正（アクティブなカテゴリのみに制限）
        // 既存のインデックスを削除
        sqlite3_exec(db, "DROP INDEX IF EXISTS idx_category_name;", nil, nil, nil)
        
        // アクティブなカテゴリのみにユニーク制約を適用
        let createIndexString = "CREATE UNIQUE INDEX IF NOT EXISTS idx_category_name_active ON Category(name) WHERE isActive = 1;"
        let indexResult = sqlite3_exec(db, createIndexString, nil, nil, nil)
        if indexResult == SQLITE_OK {
            print("✅ ユニークインデックス作成成功")
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ ユニークインデックス作成失敗: \(errorMessage)")
        }
        
        // デフォルトカテゴリの設定を更新
        updateDefaultCategoriesSettings()
        
        print("🔧 データベースマイグレーション完了")
    }

    private func insertDefaultCategories() {
        guard db != nil else {
            print("Database is not available.")
            return
        }
        
        // デフォルトカテゴリの定義を更新
        let defaultCategories = [
            ("食費", "fork.knife", "green", 1),
            ("交通費", "car.fill", "blue", 2),
            ("娯楽", "gamecontroller.fill", "purple", 3),
            ("家賃", "house.fill", "orange", 4)
        ]
        
        for (name, icon, color, sortOrder) in defaultCategories {
            let insertString = """
            INSERT INTO Category (name, icon, color, isDefault, isVisible, isActive, sortOrder, createdAt) 
            SELECT ?, ?, ?, 1, 1, 1, ?, datetime('now') 
            WHERE NOT EXISTS (SELECT 1 FROM Category WHERE name = ? AND isActive = 1);
            """
            var insertStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, insertString, -1, &insertStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(insertStatement, 1, (name as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStatement, 2, (icon as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStatement, 3, (color as NSString).utf8String, -1, nil)
                sqlite3_bind_int(insertStatement, 4, Int32(sortOrder))
                sqlite3_bind_text(insertStatement, 5, (name as NSString).utf8String, -1, nil)
                
                if sqlite3_step(insertStatement) == SQLITE_DONE {
                    print("✅ デフォルトカテゴリ追加: \(name)")
                }
            }
            sqlite3_finalize(insertStatement)
        }
    }
    
    private func updateDefaultCategoriesSettings() {
        guard db != nil else { return }
        
        // 既存のデフォルトカテゴリの設定を更新
        let defaultCategoriesInfo = [
            ("食費", "fork.knife", "green"),
            ("交通費", "car.fill", "blue"),
            ("娯楽", "gamecontroller.fill", "purple"),
            ("家賃", "house.fill", "orange")
        ]
        
        for (name, icon, color) in defaultCategoriesInfo {
            let updateString = """
            UPDATE Category 
            SET icon = ?, color = ?, isDefault = 1, isVisible = 1, isActive = 1
            WHERE name = ? AND isActive = 1;
            """
            var updateStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, updateString, -1, &updateStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(updateStatement, 1, (icon as NSString).utf8String, -1, nil)
                sqlite3_bind_text(updateStatement, 2, (color as NSString).utf8String, -1, nil)
                sqlite3_bind_text(updateStatement, 3, (name as NSString).utf8String, -1, nil)
                sqlite3_step(updateStatement)
            }
            sqlite3_finalize(updateStatement)
        }
    }

    // MARK: - カテゴリ管理機能
    
    func fetchCategories() -> [(id: Int, name: String)] {
        // 既存のメソッドは後方互換性のため保持
        let fullCategories = fetchFullCategories()
        return fullCategories.map { (id: $0.id, name: $0.name) }
    }
    
    func fetchFullCategories() -> [FullCategory] {
        guard db != nil else {
            print("Database is not available.")
            return []
        }
        
        // まずカラムの存在を確認してからクエリを実行
        let queryString: String
        if columnExists("createdAt", in: "Category") {
            queryString = """
            SELECT id, name, icon, color, isDefault, isVisible, isActive, sortOrder, 
                   COALESCE(createdAt, '') as createdAt 
            FROM Category 
            WHERE isActive = 1 
            ORDER BY sortOrder, id;
            """
        } else {
            queryString = """
            SELECT id, name, icon, color, isDefault, isVisible, isActive, sortOrder, 
                   '' as createdAt 
            FROM Category 
            WHERE isActive = 1 
            ORDER BY sortOrder, id;
            """
        }
        
        var queryStatement: OpaquePointer?
        var categories: [FullCategory] = []
        
        if sqlite3_prepare_v2(db, queryString, -1, &queryStatement, nil) == SQLITE_OK {
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(queryStatement, 0))
                let name = String(cString: sqlite3_column_text(queryStatement, 1))
                let icon = String(cString: sqlite3_column_text(queryStatement, 2))
                let color = String(cString: sqlite3_column_text(queryStatement, 3))
                let isDefault = sqlite3_column_int(queryStatement, 4) == 1
                let isVisible = sqlite3_column_int(queryStatement, 5) == 1
                let isActive = sqlite3_column_int(queryStatement, 6) == 1
                let sortOrder = Int(sqlite3_column_int(queryStatement, 7))
                let createdAt = String(cString: sqlite3_column_text(queryStatement, 8))
                
                let category = FullCategory(
                    id: id,
                    name: name,
                    icon: icon,
                    color: color,
                    isDefault: isDefault,
                    isVisible: isVisible,
                    isActive: isActive,
                    sortOrder: sortOrder,
                    createdAt: createdAt
                )
                categories.append(category)
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ カテゴリ取得エラー: \(errorMessage)")
        }
        sqlite3_finalize(queryStatement)
        
        print("📋 取得したカテゴリ数: \(categories.count)")
        for category in categories {
            print("  - ID:\(category.id), 名前:\(category.name), デフォルト:\(category.isDefault)")
        }
        
        return categories
    }
    
    // カラム存在確認のヘルパーメソッド
    private func columnExists(_ columnName: String, in tableName: String) -> Bool {
        guard db != nil else { return false }
        
        let pragmaQuery = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?
        var exists = false
        
        if sqlite3_prepare_v2(db, pragmaQuery, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let namePtr = sqlite3_column_text(statement, 1) {
                    let name = String(cString: namePtr)
                    if name == columnName {
                        exists = true
                        break
                    }
                }
            }
        }
        sqlite3_finalize(statement)
        return exists
    }
    
    func fetchVisibleCategories() -> [FullCategory] {
        return fetchFullCategories().filter { $0.isVisible }
    }
    
    // MARK: - 修正3: insertCategoryメソッドの改良
    func insertCategory(_ category: FullCategory) {
        guard db != nil else {
            print("❌ Database is not available.")
            return
        }
        
        beginTransaction()
        
        // 🔥 修正：アクティブなカテゴリのみで重複チェック
        if isCategoryNameExists(category.name) {
            print("❌ Category name '\(category.name)' already exists among active categories.")
            rollbackTransaction()
            return
        }
        
        // 🔥 追加：同じ名前の削除済みカテゴリがある場合、完全に削除してから新規作成
        let deleteOldString = "DELETE FROM Category WHERE name = ? AND isActive = 0;"
        var deleteStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteOldString, -1, &deleteStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(deleteStatement, 1, (category.name as NSString).utf8String, -1, nil)
            if sqlite3_step(deleteStatement) == SQLITE_DONE {
                print("🗑️ Deleted old inactive category with same name: \(category.name)")
            }
        }
        sqlite3_finalize(deleteStatement)
        
        let insertString = """
        INSERT INTO Category (name, icon, color, isDefault, isVisible, isActive, sortOrder, createdAt) 
        VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'));
        """
        var insertStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertString, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStatement, 1, (category.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 2, (category.icon as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 3, (category.color as NSString).utf8String, -1, nil)
            sqlite3_bind_int(insertStatement, 4, category.isDefault ? 1 : 0)
            sqlite3_bind_int(insertStatement, 5, category.isVisible ? 1 : 0)
            sqlite3_bind_int(insertStatement, 6, category.isActive ? 1 : 0)
            sqlite3_bind_int(insertStatement, 7, Int32(category.sortOrder))

            if sqlite3_step(insertStatement) == SQLITE_DONE {
                print("✅ Successfully inserted category: \(category.name)")
                commitTransaction()
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("❌ Could not insert category: \(errorMessage)")
                rollbackTransaction()
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ INSERT category statement could not be prepared: \(errorMessage)")
            rollbackTransaction()
        }
        sqlite3_finalize(insertStatement)
    }
    
    // MARK: - 修正4: updateCategoryメソッドの改良
    func updateCategory(_ category: FullCategory) {
        guard db != nil else {
            print("❌ Database is not available.")
            return
        }
        
        beginTransaction()
        
        // 🔥 修正：名前が変更される場合の重複チェック
        let currentName = getCurrentCategoryName(id: category.id)
        if currentName != category.name {
            // 名前が変更される場合のみ重複チェック
            if isCategoryNameExists(category.name) {
                print("❌ Category name '\(category.name)' already exists among active categories.")
                rollbackTransaction()
                return
            }
            
            // 🔥 追加：同じ名前の削除済みカテゴリがある場合、完全に削除
            let deleteOldString = "DELETE FROM Category WHERE name = ? AND isActive = 0 AND id != ?;"
            var deleteStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteOldString, -1, &deleteStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(deleteStatement, 1, (category.name as NSString).utf8String, -1, nil)
                sqlite3_bind_int(deleteStatement, 2, Int32(category.id))
                if sqlite3_step(deleteStatement) == SQLITE_DONE {
                    print("🗑️ Deleted old inactive category with same name: \(category.name)")
                }
            }
            sqlite3_finalize(deleteStatement)
        }
        
        let updateString = """
        UPDATE Category
        SET name = ?, icon = ?, color = ?, isVisible = ?, sortOrder = ?
        WHERE id = ? AND isActive = 1;
        """
        var updateStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateString, -1, &updateStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(updateStatement, 1, (category.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(updateStatement, 2, (category.icon as NSString).utf8String, -1, nil)
            sqlite3_bind_text(updateStatement, 3, (category.color as NSString).utf8String, -1, nil)
            sqlite3_bind_int(updateStatement, 4, category.isVisible ? 1 : 0)
            sqlite3_bind_int(updateStatement, 5, Int32(category.sortOrder))
            sqlite3_bind_int(updateStatement, 6, Int32(category.id))

            if sqlite3_step(updateStatement) == SQLITE_DONE {
                print("✅ Successfully updated category: \(category.name)")
                commitTransaction()
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("❌ Could not update category: \(errorMessage)")
                rollbackTransaction()
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ UPDATE category statement could not be prepared: \(errorMessage)")
            rollbackTransaction()
        }
        sqlite3_finalize(updateStatement)
    }
    
    func updateCategoriesOrder(_ categories: [FullCategory]) {
        guard db != nil else { return }
        
        beginTransaction()
        
        for category in categories {
            let updateString = "UPDATE Category SET sortOrder = ? WHERE id = ? AND isActive = 1;"
            var updateStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, updateString, -1, &updateStatement, nil) == SQLITE_OK {
                sqlite3_bind_int(updateStatement, 1, Int32(category.sortOrder))
                sqlite3_bind_int(updateStatement, 2, Int32(category.id))
                sqlite3_step(updateStatement)
            }
            sqlite3_finalize(updateStatement)
        }
        
        commitTransaction()
        print("✅ Successfully updated categories order.")
    }
    
    func deleteCategoryLogically(id: Int) {
        guard db != nil else {
            print("❌ Database is not available.")
            return
        }
        
        // デフォルトカテゴリの削除を防ぐ
        if isCategoryDefault(id: id) {
            print("❌ Cannot delete default category with id: \(id)")
            return
        }
        
        // 使用中かチェック
        let usageCount = getCategoryUsageCount(id: id)
        if usageCount > 0 {
            print("⚠️ Warning: Category (id: \(id)) is used in \(usageCount) expenses. Proceeding with logical deletion.")
        }
        
        beginTransaction()
        let updateString = "UPDATE Category SET isActive = 0 WHERE id = ? AND isDefault = 0;"
        var updateStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateString, -1, &updateStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(updateStatement, 1, Int32(id))
            
            if sqlite3_step(updateStatement) == SQLITE_DONE {
                print("✅ Successfully deleted category logically (id: \(id)).")
                commitTransaction()
            } else {
                let errorMessage = String(cString: sqlite3_errmsg(db))
                print("❌ Could not delete category logically: \(errorMessage)")
                rollbackTransaction()
            }
        } else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            print("❌ DELETE category statement could not be prepared: \(errorMessage)")
            rollbackTransaction()
        }
        sqlite3_finalize(updateStatement)
    }
    
    // MARK: - デフォルトカテゴリリセット機能
    func resetDefaultCategories() {
        guard db != nil else {
            print("❌ Database is not available.")
            return
        }
        
        beginTransaction()
        
        // まずデフォルトカテゴリを削除（論理削除）
        let deleteDefaultsString = "UPDATE Category SET isActive = 0 WHERE isDefault = 1;"
        sqlite3_exec(db, deleteDefaultsString, nil, nil, nil)
        
        // 削除されたデフォルトカテゴリを再作成
        let defaultCategories = [
            ("食費", "fork.knife", "green", 1),
            ("交通費", "car.fill", "blue", 2),
            ("娯楽", "gamecontroller.fill", "purple", 3),
            ("家賃", "house.fill", "orange", 4)
        ]
        
        for (name, icon, color, sortOrder) in defaultCategories {
            let insertString = """
            INSERT INTO Category (name, icon, color, isDefault, isVisible, isActive, sortOrder, createdAt) 
            VALUES (?, ?, ?, 1, 1, 1, ?, datetime('now'));
            """
            var insertStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, insertString, -1, &insertStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(insertStatement, 1, (name as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStatement, 2, (icon as NSString).utf8String, -1, nil)
                sqlite3_bind_text(insertStatement, 3, (color as NSString).utf8String, -1, nil)
                sqlite3_bind_int(insertStatement, 4, Int32(sortOrder))
                sqlite3_step(insertStatement)
            }
            sqlite3_finalize(insertStatement)
        }
        
        commitTransaction()
        print("✅ Default categories have been reset.")
    }
    
    // MARK: - ヘルパーメソッド
    private func isCategoryNameExists(_ name: String) -> Bool {
        guard db != nil else { return false }
        
        // 🔥 修正：アクティブなカテゴリのみをチェック
        let queryString = "SELECT COUNT(*) FROM Category WHERE name = ? AND isActive = 1;"
        var queryStatement: OpaquePointer?
        var exists = false
        
        if sqlite3_prepare_v2(db, queryString, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(queryStatement, 1, (name as NSString).utf8String, -1, nil)
            if sqlite3_step(queryStatement) == SQLITE_ROW {
                exists = sqlite3_column_int(queryStatement, 0) > 0
            }
        }
        sqlite3_finalize(queryStatement)
        return exists
    }
    
    private func getCurrentCategoryName(id: Int) -> String {
        guard db != nil else { return "" }
        
        let queryString = "SELECT name FROM Category WHERE id = ? AND isActive = 1;"
        var queryStatement: OpaquePointer?
        var name = ""
        
        if sqlite3_prepare_v2(db, queryString, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(queryStatement, 1, Int32(id))
            if sqlite3_step(queryStatement) == SQLITE_ROW {
                name = String(cString: sqlite3_column_text(queryStatement, 0))
            }
        }
        sqlite3_finalize(queryStatement)
        return name
    }
    
    private func isCategoryDefault(id: Int) -> Bool {
        guard db != nil else { return false }
        
        let queryString = "SELECT isDefault FROM Category WHERE id = ? AND isActive = 1;"
        var queryStatement: OpaquePointer?
        var isDefault = false
        
        if sqlite3_prepare_v2(db, queryString, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(queryStatement, 1, Int32(id))
            if sqlite3_step(queryStatement) == SQLITE_ROW {
                isDefault = sqlite3_column_int(queryStatement, 0) == 1
            }
        }
        sqlite3_finalize(queryStatement)
        return isDefault
    }
    
    private func getCategoryUsageCount(id: Int) -> Int {
        guard db != nil else { return 0 }
        
        let queryString = "SELECT COUNT(*) FROM Expense WHERE categoryId = ?;"
        var queryStatement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, queryString, -1, &queryStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(queryStatement, 1, Int32(id))
            if sqlite3_step(queryStatement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(queryStatement, 0))
            }
        }
        sqlite3_finalize(queryStatement)
        return count
    }

    // MARK: - 既存のExpense関連メソッドはそのまま保持

    func insertExpense(expense: Expense) {
        guard db != nil else {
            print("Database is not available.")
            return
        }
        beginTransaction()
        let insertString = "INSERT INTO Expense (amount, date, note, categoryId, userId) VALUES (?, ?, ?, ?, ?);"
        var insertStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertString, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_double(insertStatement, 1, expense.amount)
            let formatter = ISO8601DateFormatter()
            let dateString = formatter.string(from: expense.date)
            sqlite3_bind_text(insertStatement, 2, (dateString as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStatement, 3, (expense.note as NSString).utf8String, -1, nil)
            sqlite3_bind_int(insertStatement, 4, Int32(expense.categoryId))
            sqlite3_bind_int(insertStatement, 5, Int32(expense.userId))

            if sqlite3_step(insertStatement) == SQLITE_DONE {
                print("Successfully inserted expense.")
                commitTransaction()
            } else {
                print("Could not insert expense.")
                rollbackTransaction()
            }
        } else {
            print("INSERT expense statement could not be prepared.")
            rollbackTransaction()
        }
        sqlite3_finalize(insertStatement)
    }

    func updateExpense(expense: Expense) {
        guard db != nil else {
            print("Database is not available.")
            return
        }
        beginTransaction()
        let updateString = """
        UPDATE Expense
        SET amount = ?, date = ?, note = ?, categoryId = ?, userId = ?
        WHERE id = ?;
        """
        var updateStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateString, -1, &updateStatement, nil) == SQLITE_OK {
            sqlite3_bind_double(updateStatement, 1, expense.amount)

            let formatter = ISO8601DateFormatter()
            let dateString = formatter.string(from: expense.date)
            sqlite3_bind_text(updateStatement, 2, (dateString as NSString).utf8String, -1, nil)

            sqlite3_bind_text(updateStatement, 3, (expense.note as NSString).utf8String, -1, nil)
            sqlite3_bind_int(updateStatement, 4, Int32(expense.categoryId))
            sqlite3_bind_int(updateStatement, 5, Int32(expense.userId))
            sqlite3_bind_int(updateStatement, 6, Int32(expense.id))

            if sqlite3_step(updateStatement) == SQLITE_DONE {
                print("Successfully updated expense.")
                commitTransaction()
            } else {
                print("Could not update expense.")
                rollbackTransaction()
            }
        } else {
            print("UPDATE expense statement could not be prepared.")
            rollbackTransaction()
        }
        sqlite3_finalize(updateStatement)
    }

    func fetchExpenses() -> [Expense] {
        guard db != nil else {
            print("Database is not available.")
            return []
        }
        let queryString = "SELECT id, amount, date, note, categoryId, userId FROM Expense ORDER BY date DESC;"
        var queryStatement: OpaquePointer?
        var expenses: [Expense] = []

        if sqlite3_prepare_v2(db, queryString, -1, &queryStatement, nil) == SQLITE_OK {
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(queryStatement, 0))
                let amount = sqlite3_column_double(queryStatement, 1)
                let dateString = String(cString: sqlite3_column_text(queryStatement, 2))
                let note = String(cString: sqlite3_column_text(queryStatement, 3))
                let categoryId = Int(sqlite3_column_int(queryStatement, 4))
                let userId = Int(sqlite3_column_int(queryStatement, 5))

                let formatter = ISO8601DateFormatter()
                let date = formatter.date(from: dateString) ?? Date()

                let expense = Expense(id: id, amount: amount, date: date, note: note, categoryId: categoryId, userId: userId)
                expenses.append(expense)
            }
        } else {
            print("SELECT statement could not be prepared")
        }
        sqlite3_finalize(queryStatement)
        return expenses
    }

    func deleteExpense(id: Int) {
        guard db != nil else {
            print("Database is not available.")
            return
        }
        beginTransaction()
        let deleteString = "DELETE FROM Expense WHERE id = ?;"
        var deleteStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteString, -1, &deleteStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(deleteStatement, 1, Int32(id))
            
            if sqlite3_step(deleteStatement) == SQLITE_DONE {
                print("Successfully deleted expense.")
                commitTransaction()
            } else {
                print("Could not delete expense.")
                rollbackTransaction()
            }
        } else {
            print("DELETE expense statement could not be prepared.")
            rollbackTransaction()
        }
        sqlite3_finalize(deleteStatement)
    }
}

// MARK: - データ構造

struct FullCategory {
    let id: Int
    let name: String
    let icon: String
    let color: String
    let isDefault: Bool
    let isVisible: Bool
    let isActive: Bool
    let sortOrder: Int
    let createdAt: String
    
    init(id: Int = 0, name: String, icon: String, color: String, isDefault: Bool = false, isVisible: Bool = true, isActive: Bool = true, sortOrder: Int = 0, createdAt: String = "") {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.isDefault = isDefault
        self.isVisible = isVisible
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
