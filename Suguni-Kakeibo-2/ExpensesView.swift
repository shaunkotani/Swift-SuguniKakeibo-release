import SwiftUI

struct ExpensesView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @State private var searchText = ""
    @State private var selectedExpenseId: Int? = nil
    @State private var showingDeleteConfirmation = false
    @State private var expenseToDelete: Expense?
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled

    var filteredExpenses: [Expense] {
        let expenses = viewModel.expenses.sorted(by: { $0.date > $1.date })
        
        if searchText.isEmpty {
            return expenses
        } else {
            return expenses.filter { expense in
                expense.note.localizedCaseInsensitiveContains(searchText) ||
                viewModel.categories.first(where: { $0.id == expense.categoryId })?.name.localizedCaseInsensitiveContains(searchText) == true
            }
        }
    }
    
    private var totalAmount: Double {
        filteredExpenses.reduce(0) { $0 + $1.amount }
    }
    
    private var expenseCountText: String {
        let count = filteredExpenses.count
        return count == 1 ? "1件の支出" : "\(count)件の支出"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // サマリーヘッダー（アクセシビリティ対応）
                if !filteredExpenses.isEmpty {
                    ExpenseSummaryHeaderView(
                        totalAmount: totalAmount,
                        expenseCount: filteredExpenses.count,
                        searchText: searchText
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(searchText.isEmpty ?
                        "合計支出 \(Int(totalAmount))円、\(expenseCountText)" :
                        "検索結果: 合計 \(Int(totalAmount))円、\(expenseCountText)"
                    )
                    .accessibilityHint("支出の概要情報")
                }
                
                List {
                    ForEach(filteredExpenses) { expense in
                        Button(action: {
                            selectedExpenseId = expense.id
                        }) {
                            ExpenseRowView(expense: expense, viewModel: viewModel)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(createExpenseAccessibilityLabel(for: expense))
                        .accessibilityHint("ダブルタップして編集")
                        .accessibilityAction(named: "編集") {
                            selectedExpenseId = expense.id
                        }
                        .accessibilityAction(named: "削除") {
                            expenseToDelete = expense
                            showingDeleteConfirmation = true
                        }
                    }
                    .onDelete(perform: deleteExpenses)
                }
                .listStyle(.plain)
                .accessibilityLabel("支出履歴一覧")
                .overlay {
                    if filteredExpenses.isEmpty && !searchText.isEmpty {
                        SearchEmptyStateView(searchText: searchText)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("検索結果なし。\(searchText)に一致する支出が見つかりません")
                            .accessibilityHint("別のキーワードで検索してください")
                    } else if viewModel.expenses.isEmpty {
                        GeneralEmptyStateView()
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("支出履歴がありません")
                            .accessibilityHint("入力タブから支出を追加してください")
                    }
                }
            }
            .navigationTitle("支出履歴")
            .navigationBarTitleDisplayMode(.automatic)
            .searchable(text: $searchText, prompt: "メモやカテゴリで検索")
            .accessibilityAction(.escape) {
                // VoiceOverでエスケープアクションを提供
                if !searchText.isEmpty {
                    searchText = ""
                }
            }
            .refreshable {
                viewModel.refreshAllData()
            }
            .sheet(item: Binding<ExpenseSheetItem?>(
                get: {
                    if let id = selectedExpenseId {
                        return ExpenseSheetItem(id: id)
                    }
                    return nil
                },
                set: { _ in
                    selectedExpenseId = nil
                }
            )) { item in
                NavigationStack {
                    EditExpenseView(expenseId: item.id)
                        .environmentObject(viewModel)
                }
                .accessibilityLabel("支出編集画面")
            }
            .alert("支出を削除", isPresented: $showingDeleteConfirmation) {
                Button("削除", role: .destructive) {
                    if let expense = expenseToDelete {
                        viewModel.deleteExpense(id: expense.id)
                        expenseToDelete = nil
                    }
                }
                Button("キャンセル", role: .cancel) {
                    expenseToDelete = nil
                }
            } message: {
                if let expense = expenseToDelete {
                    Text("\(Int(expense.amount))円の支出を削除しますか？この操作は取り消せません。")
                }
            }
        }
        .onAppear {
            viewModel.fetchExpenses()
        }
    }
    
    // MARK: - アクセシビリティヘルパー
    private func createExpenseAccessibilityLabel(for expense: Expense) -> String {
        let categoryName = viewModel.categoryName(for: expense.categoryId)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.locale = Locale(identifier: "ja_JP")
        let dateString = dateFormatter.string(from: expense.date)
        
        var label = "\(Int(expense.amount))円、\(categoryName)、\(dateString)"
        
        if !expense.note.isEmpty {
            label += "、メモ: \(expense.note)"
        }
        
        return label
    }
    
    private func deleteExpenses(offsets: IndexSet) {
        withAnimation(.easeInOut(duration: 0.3)) {
            for index in offsets {
                let expense = filteredExpenses[index]
                viewModel.deleteExpense(id: expense.id)
            }
        }
        
        // VoiceOver用のアナウンス
        if voiceOverEnabled {
            let count = offsets.count
            let message = count == 1 ? "1件の支出を削除しました" : "\(count)件の支出を削除しました"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
    }
}

// サマリーヘッダービュー（アクセシビリティ対応）
struct ExpenseSummaryHeaderView: View {
    let totalAmount: Double
    let expenseCount: Int
    let searchText: String
    
    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return "¥" + (formatter.string(from: NSNumber(value: totalAmount)) ?? "0")
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(searchText.isEmpty ? "合計支出" : "検索結果")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true) // ラベルで統合されるため非表示
                
                Text(formattedAmount)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .accessibilityHidden(true)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("件数")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                
                Text("\(expenseCount)件")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .accessibilityHidden(true)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.1))
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
}

// 検索結果なし状態ビュー（アクセシビリティ対応）
struct SearchEmptyStateView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text("「\(searchText)」の検索結果がありません")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
                
                Text("別のキーワードで検索してみてください")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
            }
        }
        .padding()
    }
}

// 一般的な空状態ビュー（アクセシビリティ対応）
struct GeneralEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text("支出履歴がありません")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                
                Text("「入力」タブから支出を追加してください")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding()
    }
}

// シート表示用のアイテム
struct ExpenseSheetItem: Identifiable {
    let id: Int
}

struct ExpenseRowView: View {
    let expense: Expense
    let viewModel: ExpenseViewModel
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = voiceOverEnabled ? "M月d日" : "M月d日"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var fullDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var categoryName: String {
        viewModel.categories.first(where: { $0.id == expense.categoryId })?.name ?? "不明なカテゴリ"
    }
    
    // 動的にアイコンを取得
    private var categoryIcon: String {
        return viewModel.categoryIcon(for: expense.categoryId)
    }

    // 動的に色を取得
    private var categoryColor: Color {
        let colorString = viewModel.categoryColor(for: expense.categoryId)
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
    
    var body: some View {
        HStack(spacing: 12) {
            // カテゴリアイコン
            VStack {
                Image(systemName: categoryIcon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(categoryColor)
                    .clipShape(Circle())
                    .shadow(color: categoryColor.opacity(0.3), radius: 2, x: 0, y: 1)
            }
            .accessibilityHidden(true) // 色で情報を伝える要素は隠す
            
            // メイン情報
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("¥\(expense.amount, specifier: "%.0f")")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .accessibilityHidden(true)
                    
                    Spacer()
                    
                    Text("\(expense.date, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
                
                Text(categoryName)
                    .font(.subheadline)
                    .foregroundColor(categoryColor)
                    .fontWeight(.medium)
                    .accessibilityHidden(true)
                
                if !expense.note.isEmpty {
                    Text(expense.note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .accessibilityHidden(true)
                } else if voiceOverEnabled {
                    // VoiceOverユーザーにはメモがないことを明示
                    Text("メモなし")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .italic()
                        .accessibilityHidden(true)
                }
            }
            
            // 矢印
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray.opacity(0.6))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle()) // タップ領域を明確化
        .background(Color.clear)
        .cornerRadius(8)
    }
}

struct ExpensesView_Previews: PreviewProvider {
    static var previews: some View {
        ExpensesView()
            .environmentObject(ExpenseViewModel())
    }
}
