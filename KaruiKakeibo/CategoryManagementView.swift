//
//  CategoryManagementView.swift (改良版)
//  Suguni-Kakeibo-2
//
//  Created by 大谷駿介 on 2025/08/08.
//

import SwiftUI

struct CategoryManagementView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var categories: [EditableCategory] = []
    @State private var showingAddCategory = false
    @State private var showingEditCategory: EditableCategory?
    @State private var showingDeleteConfirmation = false
    @State private var categoryToDelete: EditableCategory?
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 新規追加ボタン
                Button(action: {
                    showingAddCategory = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("新しいカテゴリを追加")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
                .padding(.bottom, 16)
                
                // 表示設定セクション
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "eye")
                            .foregroundColor(.blue)
                        Text("表示・順序設定")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.horizontal)
                    
                    Text("✓で表示/非表示、ドラッグで順序変更、タップで編集")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                .padding(.bottom, 8)
                
                // カテゴリリスト
                if categories.isEmpty && !isLoading {
                    VStack(spacing: 16) {
                        Image(systemName: "tag.circle")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("カテゴリがありません")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("上のボタンからカテゴリを追加")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        ForEach(categories) { category in
                            CategoryManagementRowView(
                                category: category,
                                onToggleVisibility: { toggleVisibility(for: category) },
                                onEdit: { showingEditCategory = category },
                                onDelete: {
                                    categoryToDelete = category
                                    showingDeleteConfirmation = true
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                        .onMove(perform: moveCategories)
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active)) // 並び替えを常時有効
                }
            }
            .navigationTitle("カテゴリ管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        loadCategories()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                    .disabled(isLoading)
                }
            }
            .onAppear {
                loadCategories()
            }
            .sheet(isPresented: $showingAddCategory) {
                CategoryEditView(category: nil) { newCategory in
                    addCategory(newCategory)
                }
                .environmentObject(viewModel)
            }
            .sheet(item: $showingEditCategory) { category in
                CategoryEditView(category: category) { updatedCategory in
                    updateCategory(updatedCategory)
                }
                .environmentObject(viewModel)
            }
            .alert("エラー", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .alert("カテゴリを削除", isPresented: $showingDeleteConfirmation) {
                Button("削除", role: .destructive) {
                    if let category = categoryToDelete {
                        deleteCategory(category)
                        categoryToDelete = nil
                    }
                }
                Button("キャンセル", role: .cancel) {
                    categoryToDelete = nil
                }
            } message: {
                if let category = categoryToDelete {
                    Text("\(category.name)を削除しますか？\n\(category.isDefault ? "デフォルトカテゴリは削除できません。" : "この操作は取り消せません。")")
                }
            }
            .overlay {
                if isLoading {
                    VStack {
                        ProgressView("読み込み中...")
                            .padding()
                            .background(Color.gray.opacity(0.8))
                            .cornerRadius(10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
                }
            }
        }
    }
    
    // MARK: - データ操作
    private func loadCategories() {
        isLoading = true
        
        // ViewModelから最新のカテゴリデータを取得
        categories = viewModel.fullCategories.map { dbCategory in
            EditableCategory(
                id: dbCategory.id,
                name: dbCategory.name,
                icon: dbCategory.icon,
                color: dbCategory.color,
                isDefault: dbCategory.isDefault,
                isVisible: dbCategory.isVisible,
                sortOrder: dbCategory.sortOrder
            )
        }.sorted { $0.sortOrder < $1.sortOrder }
        
        isLoading = false
        print("📝 カテゴリ管理画面: \(categories.count)件のカテゴリを読み込み")
    }
    
    private func toggleVisibility(for category: EditableCategory) {
        // 最低1つは表示必須のチェック
        let visibleCount = categories.filter { $0.isVisible }.count
        if visibleCount <= 1 && category.isVisible {
            // 警告を表示
            alertMessage = "最低1つのカテゴリは表示する必要があります。"
            showAlert = true
            
            // ハプティックフィードバック
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            return
        }
        
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index].isVisible.toggle()
            
            // データベースに保存
            let updatedFullCategory = FullCategory(
                id: categories[index].id,
                name: categories[index].name,
                icon: categories[index].icon,
                color: categories[index].color,
                isDefault: categories[index].isDefault,
                isVisible: categories[index].isVisible,
                isActive: true,
                sortOrder: categories[index].sortOrder
            )
            
            viewModel.updateCategory(updatedFullCategory)
            
            print("👁️ カテゴリ表示切り替え: \(category.name) -> \(categories[index].isVisible ? "表示" : "非表示")")
        }
    }
    
    private func moveCategories(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
        
        // sortOrderを更新
        for (index, _) in categories.enumerated() {
            categories[index].sortOrder = index
        }
        
        // データベースに順序を保存
        let updatedFullCategories = categories.map { category in
            FullCategory(
                id: category.id,
                name: category.name,
                icon: category.icon,
                color: category.color,
                isDefault: category.isDefault,
                isVisible: category.isVisible,
                isActive: true,
                sortOrder: category.sortOrder
            )
        }
        
        viewModel.updateCategoriesOrder(updatedFullCategories)
        print("🔄 カテゴリ順序更新: \(categories.count)件")
    }
    
    private func addCategory(_ category: EditableCategory) {
        var newCategory = category
        newCategory.sortOrder = categories.count
        
        let fullCategory = FullCategory(
            name: newCategory.name,
            icon: newCategory.icon,
            color: newCategory.color,
            isDefault: false,
            isVisible: true,
            isActive: true,
            sortOrder: newCategory.sortOrder
        )
        
        viewModel.addCategory(fullCategory)
        
        // リストを更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            loadCategories()
        }
        
        print("➕ カテゴリ追加: \(category.name)")
    }
    
    private func updateCategory(_ category: EditableCategory) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
            
            let updatedFullCategory = FullCategory(
                id: category.id,
                name: category.name,
                icon: category.icon,
                color: category.color,
                isDefault: category.isDefault,
                isVisible: category.isVisible,
                isActive: true,
                sortOrder: category.sortOrder
            )
            
            viewModel.updateCategory(updatedFullCategory)
            print("✏️ カテゴリ更新: \(category.name)")
        }
    }
    
    private func deleteCategory(_ category: EditableCategory) {
        // デフォルトカテゴリの削除を防ぐ
        if category.isDefault {
            alertMessage = "デフォルトカテゴリは削除できません。"
            showAlert = true
            return
        }
        
        viewModel.deleteCategory(id: category.id)
        
        // リストから削除
        categories.removeAll { $0.id == category.id }
        
        print("🗑️ カテゴリ削除: \(category.name)")
    }
}

// MARK: - カテゴリ行ビュー
struct CategoryManagementRowView: View {
    let category: EditableCategory
    let onToggleVisibility: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 表示/非表示チェックボックス
            Button(action: onToggleVisibility) {
                Image(systemName: category.isVisible ? "checkmark.square.fill" : "square")
                    .foregroundColor(category.isVisible ? .blue : .gray)
                    .font(.title2)
            }
            .buttonStyle(PlainButtonStyle())
            
            // カテゴリアイコン
            Image(systemName: category.icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(colorFromString(category.color))
                .clipShape(Circle())
                .opacity(category.isVisible ? 1.0 : 0.5)
            
            // カテゴリ情報
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(category.name)
                        .font(.headline)
                        .foregroundColor(category.isVisible ? .primary : .secondary)
                    
                    if category.isDefault {
                        Text("デフォルト")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                    }
                }
                
                Text(category.isVisible ? "表示中" : "非表示")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 編集・削除ボタン
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .frame(width: 32, height: 32)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                
                if !category.isDefault {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .frame(width: 32, height: 32)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
        }
        .padding(.vertical, 8)
        .background(category.isVisible ? Color.clear : Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func colorFromString(_ colorString: String) -> Color {
        switch colorString {
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "yellow": return .yellow
        case "pink": return .pink
        default: return .gray
        }
    }
}

// MARK: - カテゴリ編集ビュー
struct CategoryEditView: View {
    let category: EditableCategory?
    let onSave: (EditableCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    
    @State private var name: String = ""
    @State private var selectedIcon: String = "tag.fill"
    @State private var selectedColor: String = "gray"
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    private let availableIcons = [
        "tag.fill", "fork.knife", "car.fill", "gamecontroller.fill", "house.fill",
        "cart.fill", "creditcard.fill", "book.fill", "music.note", "heart.fill",
        "star.fill", "airplane", "bicycle", "phone.fill", "laptopcomputer",
        "questionmark.circle", "plus.circle", "minus.circle", "dollarsign.circle",
        "tshirt.fill"
    ]
    
    private let availableColors = [
        ("gray", Color.gray),
        ("blue", Color.blue),
        ("green", Color.green),
        ("orange", Color.orange),
        ("red", Color.red),
        ("purple", Color.purple),
        ("pink", Color.pink),
        ("yellow", Color.yellow)
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("カテゴリ名")) {
                    TextField("カテゴリ名を入力", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section(header: Text("アイコン")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Button(action: {
                                selectedIcon = icon
                            }) {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .frame(width: 40, height: 40)
                                    .background(selectedIcon == icon ? colorFromString(selectedColor) : Color.gray.opacity(0.6))
                                    .clipShape(Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(selectedIcon == icon ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                }
                
                Section(header: Text("カラー")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(availableColors, id: \.0) { colorName, color in
                            Button(action: {
                                selectedColor = colorName
                            }) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .stroke(selectedColor == colorName ? Color.black : Color.clear, lineWidth: 3)
                                    )
                                    .overlay(
                                        Image(systemName: selectedIcon)
                                            .font(.caption)
                                            .foregroundColor(.white)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                }
                
                Section(header: Text("プレビュー")) {
                    HStack {
                        Image(systemName: selectedIcon)
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(colorFromString(selectedColor))
                            .clipShape(Circle())
                        
                        VStack(alignment: .leading) {
                            Text(name.isEmpty ? "カテゴリ名" : name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("プレビュー")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorFromString(selectedColor).opacity(0.1))
                            .stroke(colorFromString(selectedColor).opacity(0.3), lineWidth: 1)
                    )
                }
            }
            .navigationTitle(category == nil ? "新規カテゴリ" : "カテゴリ編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveCategory()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let existingCategory = category {
                    name = existingCategory.name
                    selectedIcon = existingCategory.icon
                    selectedColor = existingCategory.color
                }
            }
            .alert("入力エラー", isPresented: $showAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func saveCategory() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty else {
            alertMessage = "カテゴリ名を入力"
            showAlert = true
            return
        }
        
        // 重複チェック（編集時は自分以外）
        let existingCategories = viewModel.fullCategories
        let isDuplicate = existingCategories.contains { existingCategory in
            existingCategory.name == trimmedName && existingCategory.id != (category?.id ?? -1)
        }
        
        if isDuplicate {
            alertMessage = "同じ名前のカテゴリが既に存在しています"
            showAlert = true
            return
        }
        
        let editableCategory = EditableCategory(
            id: category?.id ?? 0,
            name: trimmedName,
            icon: selectedIcon,
            color: selectedColor,
            isDefault: category?.isDefault ?? false,
            isVisible: category?.isVisible ?? true,
            sortOrder: category?.sortOrder ?? 0
        )
        
        onSave(editableCategory)
        dismiss()
    }
    
    private func colorFromString(_ colorString: String) -> Color {
        switch colorString {
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        case "yellow": return .yellow
        case "pink": return .pink
        default: return .gray
        }
    }
}

// MARK: - データモデル
struct EditableCategory: Identifiable {
    var id: Int
    var name: String
    var icon: String
    var color: String
    var isDefault: Bool
    var isVisible: Bool
    var sortOrder: Int
    
    init(id: Int = 0, name: String, icon: String, color: String, isDefault: Bool = false, isVisible: Bool = true, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
        self.isDefault = isDefault
        self.isVisible = isVisible
        self.sortOrder = sortOrder
    }
}

struct CategoryManagementView_Previews: PreviewProvider {
    static var previews: some View {
        CategoryManagementView()
            .environmentObject(ExpenseViewModel())
    }
}
