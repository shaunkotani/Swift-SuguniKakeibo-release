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
                // 検索条件
                let matchesNote = expense.note.localizedCaseInsensitiveContains(searchText)
                let matchesCategory = viewModel.categories.first(where: { $0.id == expense.categoryId })?.name.localizedCaseInsensitiveContains(searchText) == true
                let matchesAmount = matchesAmountSearch(expense: expense, searchText: searchText)
                
                return matchesNote || matchesCategory || matchesAmount
            }
        }
    }
    
    // 金額検索のマッチング関数
    private func matchesAmountSearch(expense: Expense, searchText: String) -> Bool {
        let cleanSearchText = searchText.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        
        // 空の場合や数値でない場合はfalse
        guard !cleanSearchText.isEmpty, let searchAmount = Double(cleanSearchText) else {
            // 円記号やカンマ付きの場合の処理
            let currencyRemovedText = searchText
                .replacingOccurrences(of: "¥", with: "")
                .replacingOccurrences(of: "円", with: "")
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let searchAmount = Double(currencyRemovedText) {
                return matchesAmountValue(expense.amount, searchAmount: searchAmount)
            }
            return false
        }
        
        return matchesAmountValue(expense.amount, searchAmount: searchAmount)
    }
    
    // 金額マッチングのロジック
    private func matchesAmountValue(_ expenseAmount: Double, searchAmount: Double) -> Bool {
        // 完全一致
        if expenseAmount == searchAmount {
            return true
        }
        
        // 文字列として部分一致（例：「500」で「1500」にマッチ）
        let expenseAmountString = String(format: "%.0f", expenseAmount)
        let searchAmountString = String(format: "%.0f", searchAmount)
        
        return expenseAmountString.contains(searchAmountString)
    }
    
    private var totalAmount: Double {
        filteredExpenses.reduce(0) { $0 + $1.amount }
    }
    
    private var expenseCountText: String {
        let count = filteredExpenses.count
        return count == 1 ? "1件の支出" : "\(count)件の支出"
    }

    // 検索ヒントテキストを簡素化
    private var searchPrompt: String {
        return "メモ、カテゴリ、金額で検索"
    }
    
    // 数値検索かどうかを判定
    private func isNumericSearch(_ text: String) -> Bool {
        let cleanText = text
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "円", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return Double(cleanText) != nil
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
                
                // 検索ヒント表示（検索中のみ）
                if !searchText.isEmpty {
                    SearchHintView(
                        searchText: searchText,
                        isNumericSearch: isNumericSearch(searchText),
                        resultCount: filteredExpenses.count
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                List {
                    ForEach(filteredExpenses) { expense in
                        Button(action: {
                            selectedExpenseId = expense.id
                        }) {
                            ExpenseRowView(
                                expense: expense,
                                viewModel: viewModel,
                                searchText: searchText,
                                highlightAmount: isNumericSearch(searchText)
                            )
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
                        SearchEmptyStateView(
                            searchText: searchText,
                            isNumericSearch: isNumericSearch(searchText)
                        )
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
            .searchable(text: $searchText, prompt: searchPrompt)
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

// 検索ヒントビュー
struct SearchHintView: View {
    let searchText: String
    let isNumericSearch: Bool
    let resultCount: Int
    
    var body: some View {
        HStack {
            Image(systemName: isNumericSearch ? "yensign.circle" : "magnifyingglass")
                .foregroundColor(isNumericSearch ? .green : .blue)
                .font(.caption)
            
            Text(isNumericSearch ?
                 "金額「\(searchText)」で検索中 - \(resultCount)件見つかりました" :
                 "「\(searchText)」で検索中 - \(resultCount)件見つかりました")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isNumericSearch ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                .stroke(isNumericSearch ? Color.green.opacity(0.3) : Color.blue.opacity(0.3), lineWidth: 1)
        )
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

// 更新された検索結果なし状態ビュー
struct SearchEmptyStateView: View {
    let searchText: String
    let isNumericSearch: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isNumericSearch ? "yensign.circle" : "magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text(isNumericSearch ?
                     "金額「\(searchText)」の検索結果がありません" :
                     "「\(searchText)」の検索結果がありません")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
                
                if isNumericSearch {
                    Text("金額の部分一致で検索しています。例：「500」で「1500円」もヒットします")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityHidden(true)
                    
                    Text("別の金額で検索してみてください")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityHidden(true)
                } else {
                    Text("メモ、カテゴリ名、または金額で検索してみてください")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityHidden(true)
                }
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

// 更新されたExpenseRowView（検索ハイライト対応）
struct ExpenseRowView: View {
    let expense: Expense
    let viewModel: ExpenseViewModel
    let searchText: String
    let highlightAmount: Bool
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled
    
    // 修正: 日時表示を「yyyy/M/d HH:mm」形式に変更
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }
    
    private var categoryName: String {
        viewModel.categories.first(where: { $0.id == expense.categoryId })?.name ?? "不明なカテゴリ"
    }
    
    private var categoryIcon: String {
        return viewModel.categoryIcon(for: expense.categoryId)
    }

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
            .accessibilityHidden(true)
            
            // メイン情報
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // 金額検索時はハイライト
                    Text("¥\(expense.amount, specifier: "%.0f")")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(highlightAmount ? .green : .primary)
                        .background(
                            highlightAmount ?
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green.opacity(0.2))
                                .padding(.horizontal, -4)
                                .padding(.vertical, -2) :
                            nil
                        )
                        .accessibilityHidden(true)
                    
                    Spacer()
                    
                    // 修正: 日時表示を統一フォーマットに変更
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
        .contentShape(Rectangle())
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
