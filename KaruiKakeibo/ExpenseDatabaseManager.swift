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
    
    func ensureUnknownCategoryExists() {
        _ = getOrCreateCategoryId(name: "不明", icon: "questionmark.circle", color: "gray", sortOrder: 999)
    }

    func getOrCreateCategoryId(name: String, icon: String, color: String, sortOrder: Int) -> Int {
        guard db != nil else { return 0 }

        // 既にあるならID取得
        let selectSQL = "SELECT id FROM Category WHERE name = ? AND isActive = 1 LIMIT 1;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, selectSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (name as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(stmt, 0))
                sqlite3_finalize(stmt)
                return id
            }
        }
        sqlite3_finalize(stmt)

        // 無ければ作る
        beginTransaction()
        let insertSQL = """
        INSERT INTO Category (name, icon, color, isDefault, isVisible, isActive, sortOrder, createdAt, type)
        VALUES (?, ?, ?, 0, 1, 1, ?, datetime('now'), 0);
        """
        var insertStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &insertStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(insertStmt, 1, (name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStmt, 2, (icon as NSString).utf8String, -1, nil)
            sqlite3_bind_text(insertStmt, 3, (color as NSString).utf8String, -1, nil)
            sqlite3_bind_int(insertStmt, 4, Int32(sortOrder))

            if sqlite3_step(insertStmt) == SQLITE_DONE {
                let newId = Int(sqlite3_last_insert_rowid(db))
                sqlite3_finalize(insertStmt)
                commitTransaction()
                return newId
            }
        }
        sqlite3_finalize(insertStmt)
        rollbackTransaction()
        return 0
    }
    
    func insertExpenses(expenses: [Expense]) {
        guard db != nil else { return }
        guard !expenses.isEmpty else { return }

        beginTransaction()
        let sql = "INSERT INTO Expense (amount, type, date, note, categoryId, userId) VALUES (?, ?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            rollbackTransaction()
            return
        }

        let formatter = ISO8601DateFormatter()

        for e in expenses {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            sqlite3_bind_double(stmt, 1, e.amount)
            sqlite3_bind_int(stmt, 2, Int32(e.type.rawValue))
            
            let dateString = formatter.string(from: e.date)
            sqlite3_bind_text(stmt, 3, (dateString as NSString).utf8String, -1, nil)
            
            sqlite3_bind_text(stmt, 4, (e.note as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 5, Int32(e.categoryId))
            sqlite3_bind_int(stmt, 6, Int32(e.userId))

            if sqlite3_step(stmt) != SQLITE_DONE {
                sqlite3_finalize(stmt)
                rollbackTransaction()
                return
            }
        }

        sqlite3_finalize(stmt)
        commitTransaction()
    }
    
    func createCategoriesIfNeeded(names: [String], defaultIcon: String, defaultColor: String) {
        guard db != nil else { return }
        guard !names.isEmpty else { return }

        // 既存最大sortOrderの次から割り当て
        var sort = getMaxCategorySortOrder() + 1

        beginTransaction()

        let insertSQL = """
        INSERT INTO Category (name, icon, color, isDefault, isVisible, isActive, sortOrder, createdAt, type)
        VALUES (?, ?, ?, 0, 1, 1, ?, datetime('now'), 0);
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) != SQLITE_OK {
            rollbackTransaction()
            return
        }

        for name in names {
            // 念のため空はスキップ
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            sqlite3_bind_text(stmt, 1, (trimmed as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (defaultIcon as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (defaultColor as NSString).utf8String, -1, nil)
            sqlite3_bind_int(stmt, 4, Int32(sort))

            if sqlite3_step(stmt) != SQLITE_DONE {
                sqlite3_finalize(stmt)
                rollbackTransaction()
                return
            }

            sort += 1
        }

        sqlite3_finalize(stmt)
        commitTransaction()
    }

    private func getMaxCategorySortOrder() -> Int {
        guard db != nil else { return 0 }
        let sql = "SELECT COALESCE(MAX(sortOrder), 0) FROM Category;"
        var stmt: OpaquePointer?
        var maxVal = 0

        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                maxVal = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return maxVal
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
        type INTEGER DEFAULT 0,
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
        createdAt TEXT DEFAULT '',
        type INTEGER DEFAULT 0);
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
            ("createdAt", "TEXT DEFAULT ''"),
            ("type", "INTEGER DEFAULT 0") // 0=expense, 1=income
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
        
        // 既存データの整合性: Category.type の NULL を 0(支出) に初期化
        if columnExists("type", in: "Category") {
            let normalizeTypeSQL = "UPDATE Category SET type = 0 WHERE type IS NULL;"
            let normResult = sqlite3_exec(db, normalizeTypeSQL, nil, nil, nil)
            if normResult == SQLITE_OK {
                print("✅ 既存カテゴリの type を 0(支出) に初期化しました")
            } else {
                let err = String(cString: sqlite3_errmsg(db))
                print("❌ Category.type 初期化失敗: \(err)")
            }
        }
        
        // 収入にも対応
        let expenseColumnsToAdd = [
            ("type", "INTEGER DEFAULT 0")
        ]
        
        for (columnName, columnDefinition) in expenseColumnsToAdd {
            if !columnExists(columnName, in: "Expense") {
                let alterSQL = "ALTER TABLE Expense ADD COLUMN \(columnName) \(columnDefinition);"
                let result = sqlite3_exec(db, alterSQL, nil, nil, nil)
                if result == SQLITE_OK {
                    print("✅ Expenseカラム追加成功: \(columnName)")
                } else {
                    let errorMessage = String(cString: sqlite3_errmsg(db))
                    print("❌ Expenseカラム追加失敗: \(columnName) - \(errorMessage)")
                }
            } else {
                print("⚪ Expenseカラム既存: \(columnName)")
            }
        }
        
        // 修正：UNIQUEインデックスを修正（アクティブなカテゴリのみに制限）
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
        // 初回のみVisibleを設定する必要がある
        setInitialDefaultCategoriesVisibility()
        
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
            INSERT INTO Category (name, icon, color, isDefault, isVisible, isActive, sortOrder, createdAt, type) 
            SELECT ?, ?, ?, 1, 1, 1, ?, datetime('now'), 0 
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
            // 🔥 修正：isVisibleを除外して、ユーザー設定を保持
            let updateString = """
            UPDATE Category 
            SET icon = ?, color = ?, isDefault = 1, isActive = 1
            WHERE name = ? AND isActive = 1;
            """
            var updateStatement: OpaquePointer?
            if sqlite3_prepare_v2(db, updateString, -1, &updateStatement, nil) == SQLITE_OK {
                sqlite3_bind_text(updateStatement, 1, (icon as NSString).utf8String, -1, nil)
                sqlite3_bind_text(updateStatement, 2, (color as NSString).utf8String, -1, nil)
                sqlite3_bind_text(updateStatement, 3, (name as NSString).utf8String, -1, nil)
                
                if sqlite3_step(updateStatement) == SQLITE_DONE {
                    print("✅ デフォルトカテゴリ更新（isVisibleを保持）: \(name)")
                }
            }
            sqlite3_finalize(updateStatement)
        }
    }
    
    // さらに安全にするため、マイグレーション時の初回のみisVisibleを設定
    private func setInitialDefaultCategoriesVisibility() {
        guard db != nil else { return }
        
        // 初回のみ実行するためのフラグチェック
        let checkString = "SELECT COUNT(*) FROM Category WHERE isDefault = 1 AND isVisible IS NOT NULL;"
        var checkStatement: OpaquePointer?
        var hasVisibilitySet = false
        
        if sqlite3_prepare_v2(db, checkString, -1, &checkStatement, nil) == SQLITE_OK {
            if sqlite3_step(checkStatement) == SQLITE_ROW {
                let count = sqlite3_column_int(checkStatement, 0)
                hasVisibilitySet = count > 0
            }
        }
        sqlite3_finalize(checkStatement)
        
        // 初回のみisVisibleを1に設定
        if !hasVisibilitySet {
            let updateString = """
            UPDATE Category 
            SET isVisible = 1 
            WHERE isDefault = 1 AND isActive = 1 AND isVisible IS NULL;
            """
            let result = sqlite3_exec(db, updateString, nil, nil, nil)
            if result == SQLITE_OK {
                print("✅ デフォルトカテゴリの初期isVisible設定完了")
            }
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
        
        let hasCreatedAt = columnExists("createdAt", in: "Category")
        let hasType = columnExists("type", in: "Category")
        
        let queryString: String = {
            switch (hasCreatedAt, hasType) {
            case (true, true):
                return """
                SELECT id, name, icon, color, isDefault, isVisible, isActive, sortOrder, 
                       COALESCE(createdAt, '') as createdAt, COALESCE(type, 0) as type
                FROM Category 
                WHERE isActive = 1 
                ORDER BY sortOrder, id;
                """
            case (true, false):
                return """
                SELECT id, name, icon, color, isDefault, isVisible, isActive, sortOrder, 
                       COALESCE(createdAt, '') as createdAt
                FROM Category 
                WHERE isActive = 1 
                ORDER BY sortOrder, id;
                """
            case (false, true):
                return """
                SELECT id, name, icon, color, isDefault, isVisible, isActive, sortOrder, 
                       '' as createdAt, COALESCE(type, 0) as type
                FROM Category 
                WHERE isActive = 1 
                ORDER BY sortOrder, id;
                """
            default:
                return """
                SELECT id, name, icon, color, isDefault, isVisible, isActive, sortOrder
                FROM Category 
                WHERE isActive = 1 
                ORDER BY sortOrder, id;
                """
            }
        }()
        
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
                
                var createdAt = ""
                var typeRaw = 0
                if hasCreatedAt && hasType {
                    createdAt = String(cString: sqlite3_column_text(queryStatement, 8))
                    typeRaw = Int(sqlite3_column_int(queryStatement, 9))
                } else if hasCreatedAt && !hasType {
                    createdAt = String(cString: sqlite3_column_text(queryStatement, 8))
                } else if !hasCreatedAt && hasType {
                    typeRaw = Int(sqlite3_column_int(queryStatement, 8))
                }
                
                let category = FullCategory(
                    id: id,
                    name: name,
                    icon: icon,
                    color: color,
                    isDefault: isDefault,
                    isVisible: isVisible,
                    isActive: isActive,
                    sortOrder: sortOrder,
                    createdAt: createdAt,
                    type: TransactionType(rawValue: typeRaw) ?? .expense
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
            print("  - ID:\(category.id), 名前:\(category.name), デフォルト:\(category.isDefault), 種類:\(category.type)")
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
        INSERT INTO Category (name, icon, color, isDefault, isVisible, isActive, sortOrder, createdAt, type) 
        VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'), ?);
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
            sqlite3_bind_int(insertStatement, 8, Int32(category.type.rawValue))

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
        SET name = ?, icon = ?, color = ?, isVisible = ?, sortOrder = ?, type = ?
        WHERE id = ? AND isActive = 1;
        """
        var updateStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateString, -1, &updateStatement, nil) == SQLITE_OK {
            sqlite3_bind_text(updateStatement, 1, (category.name as NSString).utf8String, -1, nil)
            sqlite3_bind_text(updateStatement, 2, (category.icon as NSString).utf8String, -1, nil)
            sqlite3_bind_text(updateStatement, 3, (category.color as NSString).utf8String, -1, nil)
            sqlite3_bind_int(updateStatement, 4, category.isVisible ? 1 : 0)
            sqlite3_bind_int(updateStatement, 5, Int32(category.sortOrder))
            sqlite3_bind_int(updateStatement, 6, Int32(category.type.rawValue))
            sqlite3_bind_int(updateStatement, 7, Int32(category.id))

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
            INSERT INTO Category (name, icon, color, isDefault, isVisible, isActive, sortOrder, createdAt, type) 
            VALUES (?, ?, ?, 1, 1, 1, ?, datetime('now'), 0);
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
        let insertString = "INSERT INTO Expense (amount, type, date, note, categoryId, userId) VALUES (?, ?, ?, ?, ?, ?);"
        var insertStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertString, -1, &insertStatement, nil) == SQLITE_OK {
            sqlite3_bind_double(insertStatement, 1, expense.amount)
            sqlite3_bind_int(insertStatement, 2, Int32(expense.type.rawValue))
            
            let formatter = ISO8601DateFormatter()
            let dateString = formatter.string(from: expense.date)
            sqlite3_bind_text(insertStatement, 3, (dateString as NSString).utf8String, -1, nil)
            
            sqlite3_bind_text(insertStatement, 4, (expense.note as NSString).utf8String, -1, nil)
            sqlite3_bind_int(insertStatement, 5, Int32(expense.categoryId))
            sqlite3_bind_int(insertStatement, 6, Int32(expense.userId))

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
        SET amount = ?, type = ?, date = ?, note = ?, categoryId = ?, userId = ?
        WHERE id = ?;
        """
        var updateStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, updateString, -1, &updateStatement, nil) == SQLITE_OK {
            sqlite3_bind_double(updateStatement, 1, expense.amount)
            sqlite3_bind_int(updateStatement, 2, Int32(expense.type.rawValue))

            let formatter = ISO8601DateFormatter()
            let dateString = formatter.string(from: expense.date)
            sqlite3_bind_text(updateStatement, 3, (dateString as NSString).utf8String, -1, nil)

            sqlite3_bind_text(updateStatement, 4, (expense.note as NSString).utf8String, -1, nil)
            sqlite3_bind_int(updateStatement, 5, Int32(expense.categoryId))
            sqlite3_bind_int(updateStatement, 6, Int32(expense.userId))
            sqlite3_bind_int(updateStatement, 7, Int32(expense.id))

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
        let queryString = "SELECT id, amount, type, date, note, categoryId, userId FROM Expense ORDER BY date DESC;"
        var queryStatement: OpaquePointer?
        var expenses: [Expense] = []

        if sqlite3_prepare_v2(db, queryString, -1, &queryStatement, nil) == SQLITE_OK {
            while sqlite3_step(queryStatement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int(queryStatement, 0))
                let amount = sqlite3_column_double(queryStatement, 1)
                let typeRaw = Int(sqlite3_column_int(queryStatement, 2))
                let dateString = String(cString: sqlite3_column_text(queryStatement, 3))
                let note = String(cString: sqlite3_column_text(queryStatement, 4))
                let categoryId = Int(sqlite3_column_int(queryStatement, 5))
                let userId = Int(sqlite3_column_int(queryStatement, 6))

                let formatter = ISO8601DateFormatter()
                let date = formatter.date(from: dateString) ?? Date()
                let type = TransactionType(rawValue: typeRaw) ?? .expense

                let expense = Expense(
                    id: id,
                    amount: amount,
                    type: type,
                    date: date,
                    note: note,
                    categoryId: categoryId,
                    userId: userId
                )
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
    let type: TransactionType
    
    init(id: Int = 0, name: String, icon: String, color: String, isDefault: Bool = false, isVisible: Bool = true, isActive: Bool = true, sortOrder: Int = 0, createdAt: String = "", type: TransactionType = .expense) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.isDefault = isDefault
        self.isVisible = isVisible
        self.isActive = isActive
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.type = type
    }
}
