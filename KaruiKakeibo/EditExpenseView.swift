//
//  EditExpenseView.swift (時刻選択対応版)
//  Suguni-Kakeibo-2
//

import SwiftUI

struct EditExpenseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: ExpenseViewModel
    
    let expenseId: Int
    @State private var amount: String = ""
    @State private var date = Date()
    @State private var note: String = ""
    @State private var transactionType: TransactionType = .expense
    @State private var selectedCategoryId: Int = 1
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isUpdating = false
    @State private var alertType: AlertType = .error
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isNoteFocused: Bool
    
    enum AlertType {
        case error
        case delete
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("種類")) {
                    Picker("種類", selection: $transactionType) {
                        Text("支出")
                            .tag(TransactionType.expense)
                        Text("収入")
                            .tag(TransactionType.income)
                    }
                    .pickerStyle(.segmented)
                }
                Section(header: Text("金額")) {
                    HStack {
                        Text("¥")
                            .foregroundColor(.secondary)
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                            .fontWeight(.medium)
                            .focused($isAmountFocused)
                            .onChange(of: amount) { newValue in
                                amount = formatAmountInput(newValue)
                            }
                        
                        // 千円区切り表示
                        if let formattedAmount = getFormattedDisplayAmount() {
                            Text("(\(formattedAmount))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .animation(.easeInOut(duration: 0.2), value: amount)
                        }
                    }
                }
                
                // 修正: 日付と時刻を同時に選択できるように変更
                Section(header: Text("日付と時刻")) {
                    DatePicker("日時を選択", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                }
                
                Section(header:
                    HStack {
                        Text("カテゴリ")
                        Spacer()
                        NavigationLink {
                            CategoryManagementView()
                                .environmentObject(viewModel)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                Text("編集")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.blue.opacity(0.1))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel("カテゴリを編集")
                    }
                ) {
                    // カテゴリピッカーを独立したセクションに
                    EditCategoryPickerView(
                        selectedCategoryId: $selectedCategoryId,
                        transactionType: transactionType,
                        categoriesByType: viewModel.getVisibleCategoriesByType(transactionType),
                        visibleCategoryIds: Set(viewModel.getVisibleCategories().map { $0.id }),
                        iconProvider: { id in viewModel.categoryIcon(for: id) },
                        colorProvider: { id in viewModel.categoryColor(for: id) }
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .onAppear {
                        // 初期タイプに合わせて選択を調整
                        let visible = viewModel.getVisibleCategoriesByType(transactionType)
                        if !visible.contains(where: { $0.id == selectedCategoryId }), let first = visible.first {
                            selectedCategoryId = first.id
                        }
                    }
                    .onChange(of: transactionType) { newType in
                        let visible = viewModel.getVisibleCategoriesByType(newType)
                        if !visible.contains(where: { $0.id == selectedCategoryId }) {
                            selectedCategoryId = visible.first?.id ?? selectedCategoryId
                        }
                    }
                }
                
                Section(header: Text("メモ（任意）")) {
                    TextField("メモを入力", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isNoteFocused)
                        .onChange(of: note) { newValue in
                            // メモの文字数制限（100文字）
                            if newValue.count > 100 {
                                note = String(newValue.prefix(100))
                            }
                        }
                }
                
                Section {
                    EditButtonsView(
                        isButtonEnabled: isButtonEnabled,
                        isUpdating: isUpdating,
                        updateAction: updateExpense,
                        deleteAction: {
                            alertType = .delete
                            showAlert = true
                        },
                        cancelAction: { dismiss() }
                    )
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                
                // エラーメッセージ表示
                if let errorMessage = viewModel.errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                            Button("閉じる") {
                                viewModel.clearError()
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(Color.red.opacity(0.05))
                    }
                }
            }
            .navigationTitle(transactionType == .expense ? "支出編集" : "収入編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    // 金額入力用のツールバー
                    if isAmountFocused {
                        HStack {
                            // よく使う金額のショートカット
                            ForEach([100, 500, 1000], id: \.self) { value in
                                Button("\(value)円") {
                                    amount = String(value)
                                    // ハプティックフィードバック
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                }
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                            Spacer()
                        }
                        .frame(minWidth: 200)
                    } else {
                        Spacer()
                    }
                    
                    Button("完了") {
                        hideKeyboard()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadExpenseData()
            }
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        hideKeyboard()
                    }
            )
            .alert(alertTitle, isPresented: $showAlert) {
                if alertType == .error {
                    Button("OK") { }
                } else {
                    Button("削除", role: .destructive) {
                        deleteExpense()
                    }
                    Button("キャンセル", role: .cancel) { }
                }
            } message: {
                Text(alertBody)
            }
            .overlay {
                if isUpdating {
                    VStack {
                        ProgressView("更新中...")
                            .padding()
                            .background(Color.gray.opacity(0.8))
                            .cornerRadius(10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.3))
                    .allowsHitTesting(false)
                }
            }
        }
    }
    
    // MARK: - 計算プロパティを分離してコンパイラエラーを解決
    private var isButtonEnabled: Bool {
        let hasAmount = !amount.isEmpty
        let isValidAmountValue = isValidAmount(amount)
        let hasVisibleCategories = !viewModel.getVisibleCategoriesByType(transactionType).isEmpty
        let notUpdating = !isUpdating
        
        return hasAmount && isValidAmountValue && hasVisibleCategories && notUpdating
    }
    
    private var alertTitle: String {
        alertType == .error
            ? "入力エラー"
            : (transactionType == .expense ? "支出を削除" : "収入を削除")
    }
    
    private var alertBody: String {
        alertType == .error
            ? alertMessage
            : (transactionType == .expense
               ? "この支出を削除しますか？この操作は取り消せません。"
               : "この収入を削除しますか？この操作は取り消せません。")
    }
    
    // MARK: - 数値入力フォーマット関数
    private func formatAmountInput(_ input: String) -> String {
        // 空文字の場合はそのまま返す
        if input.isEmpty { return input }
        
        // 正規表現で数字とピリオドのみ許可
        let filtered = input.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        
        // ピリオドで分割
        let parts = filtered.components(separatedBy: ".")
        
        if parts.count > 2 {
            // 複数のピリオドを防ぐ（最初の2つのパートのみ使用）
            return parts[0] + "." + parts.dropFirst().joined()
        } else if parts.count == 2 && parts[1].count > 2 {
            // 小数点以下2桁まで制限
            return parts[0] + "." + String(parts[1].prefix(2))
        } else if parts[0].count > 10 {
            // 整数部分を10桁まで制限（100億円まで）
            return String(parts[0].prefix(10)) + (parts.count > 1 ? "." + parts[1] : "")
        }
        
        return filtered
    }
    
    private func isValidAmount(_ amountString: String) -> Bool {
        guard let value = Double(amountString) else { return false }
        return value > 0 && value <= 99999999999 // 999億円まで
    }
    
    private func getFormattedDisplayAmount() -> String? {
        guard let value = Double(amount), value >= 1000 else { return nil }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value))
    }
    
    private func hideKeyboard() {
        isAmountFocused = false
        isNoteFocused = false
    }
    
    private func loadExpenseData() {
        if let expense = viewModel.expenses.first(where: { $0.id == expenseId }) {
            // 小数点以下が0の場合は整数として表示
            if expense.amount.truncatingRemainder(dividingBy: 1) == 0 {
                amount = String(Int(expense.amount))
            } else {
                amount = String(expense.amount)
            }
            date = expense.date
            note = expense.note
            transactionType = expense.type
            selectedCategoryId = expense.categoryId
            
            let visibleTyped = viewModel.getVisibleCategoriesByType(transactionType)
            if !visibleTyped.contains(where: { $0.id == selectedCategoryId }) {
                selectedCategoryId = visibleTyped.first?.id ?? selectedCategoryId
            }
            
            print("データ読み込み完了: ID=\(expenseId), CategoryID=\(selectedCategoryId)")
            
            // 選択されたカテゴリが可視カテゴリにあるかチェック
            let visibleCategories = viewModel.getVisibleCategories()
            if !visibleCategories.contains(where: { $0.id == selectedCategoryId }) {
                print("⚠️ 警告: 選択されたカテゴリ（ID:\(selectedCategoryId)）が非表示設定されています")
            }
        }
    }
    
    private func updateExpense() {
        guard !isUpdating else { return }
        
        hideKeyboard()
        
        // より厳密な金額バリデーション
        guard !amount.isEmpty else {
            alertType = .error
            alertMessage = "金額を入力"
            showAlert = true
            return
        }
        
        guard let parsedAmount = Double(amount) else {
            alertType = .error
            alertMessage = "金額は数値で入力"
            showAlert = true
            return
        }
        
        guard parsedAmount > 0 else {
            alertType = .error
            alertMessage = "金額は0円より大きい値を入力"
            showAlert = true
            return
        }
        
        guard parsedAmount <= 99999999999 else {
            alertType = .error
            alertMessage = "金額は999億円以下で入力"
            showAlert = true
            return
        }

        // 可視カテゴリのチェック（編集時は既存カテゴリも許可）
        let allCategories = viewModel.categories
        let visibleCategories = viewModel.getVisibleCategories()
        
        if !allCategories.contains(where: { $0.id == selectedCategoryId }) {
            alertType = .error
            alertMessage = "選択されたカテゴリが存在しません。"
            showAlert = true
            return
        }
        
        // 既存の支出が非表示カテゴリを使用している場合の警告（ただし保存は許可）
        if !visibleCategories.contains(where: { $0.id == selectedCategoryId }) {
            print("⚠️ 警告: 非表示カテゴリ（ID:\(selectedCategoryId)）で更新中")
        }
        
        // 未来の日付をチェック
        if date > Date() {
            alertType = .error
            alertMessage = "未来の日時は設定できません。"
            showAlert = true
            return
        }

        isUpdating = true
        
        let updatedExpense = Expense(
            id: expenseId,
            amount: parsedAmount,
            type: transactionType,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryId: selectedCategoryId,
            userId: 1
        )
        
        // 更新処理
        viewModel.updateExpense(updatedExpense)
        
        // 少し遅延してからViewを閉じる
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isUpdating = false
            dismiss()
        }
    }
    
    private func deleteExpense() {
        viewModel.deleteExpense(id: expenseId)
        dismiss()
    }
}

// 編集用カテゴリピッカー（更新版）
struct EditCategoryPickerView: View {
    @Binding var selectedCategoryId: Int
    let transactionType: TransactionType
    let categoriesByType: [(id: Int, name: String)]
    let visibleCategoryIds: Set<Int>
    let iconProvider: (Int) -> String
    let colorProvider: (Int) -> String
    
    private var displayCategories: [(id: Int, name: String)] {
        categoriesByType
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 警告表示（選択されたカテゴリが非表示の場合）
            if !visibleCategoryIds.contains(selectedCategoryId) {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("このカテゴリは現在非表示設定です")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                    Text("保存は可能ですが、今後の入力画面では選択できません。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }
            
            // カテゴリボタンのグリッド表示
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(displayCategories, id: \.id) { category in
                    EditCategoryButtonView(
                        category: category,
                        isSelected: selectedCategoryId == category.id,
                        isVisible: visibleCategoryIds.contains(category.id),
                        iconProvider: iconProvider,
                        colorProvider: colorProvider,
                        action: {
                            selectedCategoryId = category.id
                            
                            // ハプティックフィードバック
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }
                    )
                }
            }
        }
        .padding()
    }
}

// 編集用カテゴリボタン（更新版）
struct EditCategoryButtonView: View {
    let category: (id: Int, name: String)
    let isSelected: Bool
    let isVisible: Bool
    let iconProvider: (Int) -> String
    let colorProvider: (Int) -> String
    let action: () -> Void
    
    // データベースから動的にアイコンを取得
    private var categoryIcon: String {
        iconProvider(category.id)
    }
    
    // データベースから動的に色を取得
    private var categoryColor: Color {
        let colorString = colorProvider(category.id)
        return colorFromString(colorString)
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
    
    private var strokeColor: Color {
        isSelected ? categoryColor : (isVisible ? Color.gray.opacity(0.3) : Color.orange.opacity(0.4))
    }
    private var fillColor: Color {
        isSelected ? categoryColor.opacity(0.1) : Color.gray.opacity(0.05)
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: categoryIcon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? categoryColor : Color.gray.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(color: isSelected ? categoryColor.opacity(0.3) : Color.clear, radius: 2, x: 0, y: 1)
                    .opacity(isVisible ? 1.0 : 0.6) // 非表示カテゴリは薄く表示
                
                HStack(spacing: 4) {
                    Text(category.name)
                        .font(.caption)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundColor(isSelected ? categoryColor : .secondary)
                    
                    if !isVisible {
                        Image(systemName: "eye.slash")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(strokeColor, lineWidth: isSelected ? 2 : 1)
            )
            .opacity(isVisible ? 1.0 : 0.7) // 非表示カテゴリ全体を薄く表示
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// 編集ボタンのビュー（改良版）
struct EditButtonsView: View {
    let isButtonEnabled: Bool
    let isUpdating: Bool
    let updateAction: () -> Void
    let deleteAction: () -> Void
    let cancelAction: () -> Void
    
    private var primaryButtonBackground: LinearGradient {
        if isButtonEnabled {
            return LinearGradient(
                gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            return LinearGradient(
                gradient: Gradient(colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.4)]),
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // 更新ボタン
            Button(action: updateAction) {
                HStack {
                    if isUpdating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("更新中...")
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                        Text("変更を保存")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(primaryButtonBackground)
                .cornerRadius(12)
                .shadow(color: isButtonEnabled ? Color.blue.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 2)
            }
            .disabled(!isButtonEnabled || isUpdating)
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isUpdating ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isUpdating)
            
            HStack(spacing: 12) {
                // 削除ボタン
                Button(action: deleteAction) {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("削除")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.red, Color.red.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                    .shadow(color: Color.red.opacity(0.3), radius: 2, x: 0, y: 1)
                }
                .disabled(isUpdating)
                .buttonStyle(PlainButtonStyle())
                
                // キャンセルボタン
                Button(action: cancelAction) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("キャンセル")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue, lineWidth: 2)
                            .background(Color.clear)
                    )
                }
                .disabled(isUpdating)
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct EditExpenseView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            EditExpenseView(expenseId: 1)
                .environmentObject(ExpenseViewModel())
        }
    }
}

