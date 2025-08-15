import SwiftUI

struct ExpensesView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @State private var searchText = ""
    @State private var selectedExpenseId: Int? = nil
    @State private var showingDeleteConfirmation = false
    @State private var expenseToDelete: Expense?
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled
    
    // 🎯 タブ再選択によるフォーカス制御用（iOS 18未満では代替手段を使用）
    @State private var searchFieldTrigger = false
    // 🎹 キーボード表示状態管理
    @State private var isKeyboardVisible = false

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
                            if !isKeyboardVisible {
                                selectedExpenseId = expense.id
                            }
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
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(createExpenseAccessibilityLabel(for: expense))
                        .accessibilityHint("タップして編集")
                        .accessibilityAction(named: "編集") {
                            selectedExpenseId = expense.id
                        }
                        .accessibilityAction(named: "削除") {
                            expenseToDelete = expense
                            showingDeleteConfirmation = true
                        }
                        .disabled(isKeyboardVisible)
                    }
                    .onDelete(perform: deleteExpenses)
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.immediately) // 🎹 スクロール時にキーボードを閉じる
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
            // 🎯 iOS 18未満では代替手段として検索テキストの強制更新を使用
            .onChange(of: searchFieldTrigger) { _, _ in
                // 検索フィールドにフォーカスを当てるための代替手段
                focusSearchFieldFallback()
            }
            // 🎹 キーボード用ツールバー
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if isKeyboardVisible {
                        Spacer()
                        
                        Button("閉じる") {
                            hideKeyboard()
                        }
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                    }
                }
            }
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        // キーボードが表示されている時のみ反応
                        if isKeyboardVisible {
                            hideKeyboard()
                        }
                    }
            )
            // 🔥 修正：背景タップ用の別アプローチ
            .background(
                // キーボード表示時のみ背景タップを有効にする
                Group {
                    if isKeyboardVisible {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                hideKeyboard()
                            }
                    } else {
                        Color.clear
                    }
                }
                .allowsHitTesting(isKeyboardVisible) // キーボード表示時のみタップを許可
            )
            .accessibilityAction(.escape) {
                if !searchText.isEmpty {
                    searchText = ""
                }
            }
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
            // 🎯 タブ再選択通知の監視
            .onReceive(NotificationCenter.default.publisher(for: .tabReselected)) { notification in
                // 履歴タブが再選択されたかをチェック
                if let index = notification.userInfo?["index"] as? Int,
                   index == 3 { // AppTab.expenses.rawValue
                    print("🎯 履歴タブ再選択通知を受信")
                    handleTabReselection()
                }
            }
        }
        .onAppear {
            viewModel.fetchExpenses()
            setupKeyboardObservers()
        }
        .onDisappear {
            removeKeyboardObservers()
        }
    }
    
    // 🎯 タブ再選択時の処理（iOS 17以下対応版）
    private func handleTabReselection() {
        print("🎯 handleTabReselection() 開始")
        print("🎯 現在の検索テキスト: '\(searchText)'")
        
        // iOS 18未満では直接的なフォーカス制御ができないため、
        // 検索バーのアクティブ化を促す代替手段を使用
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🎯 検索フィールドアクティブ化トリガー")
            self.searchFieldTrigger.toggle()
        }
        
        // ハプティックフィードバック
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        print("🔍 タブ再選択により検索フィールドをアクティブ化")
    }
    
    // 🎯 iOS 18未満での検索フィールドフォーカス代替手段
    private func focusSearchFieldFallback() {
        print("🎯 focusSearchFieldFallback() 実行")
        
        // UIApplication経由でキーボードの表示を試行
        DispatchQueue.main.async {
            // 検索バーの親Viewを探してfirstResponderにする試み
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
                
                // 検索バーを探してフォーカスを当てる
                self.findAndFocusSearchBar(in: keyWindow)
            }
        }
    }
    
    // 🔍 検索バーを見つけてフォーカスを当てるヘルパー関数
    private func findAndFocusSearchBar(in view: UIView) {
        for subview in view.subviews {
            // UISearchBarまたはUITextFieldを探す
            if let searchBar = subview as? UISearchBar {
                searchBar.becomeFirstResponder()
                print("🎯 UISearchBarにフォーカス設定完了")
                return
            } else if let textField = subview as? UITextField,
                      subview.accessibilityIdentifier?.contains("search") == true ||
                      textField.placeholder?.contains("検索") == true {
                textField.becomeFirstResponder()
                print("🎯 UITextFieldにフォーカス設定完了")
                return
            }
            
            // 再帰的に子ビューを探索
            findAndFocusSearchBar(in: subview)
        }
    }
    
    // MARK: - 🎹 キーボード管理
    
    // キーボード表示・非表示の監視設定
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                isKeyboardVisible = true
            }
            print("🎹 キーボード表示 - ツールバー表示")
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                isKeyboardVisible = false
            }
            print("🎹 キーボード非表示 - ツールバー非表示")
        }
    }
    
    // キーボード監視の解除
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
        print("🎹 キーボード監視解除")
    }
    
    // キーボードを閉じる
    private func hideKeyboard() {
        // 検索フィールドのフォーカスを解除してキーボードを閉じる
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        
        // ハプティックフィードバック（軽めに設定）
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        print("🎹 キーボードを手動で閉じました")
    }
    
    // スクロール開始時の追加処理（必要に応じて）
    private func handleScrollBegan() {
        // スクロール開始時にキーボードを閉じる（.scrollDismissesKeyboardと併用）
        if isKeyboardVisible {
            print("🎹 スクロール開始によりキーボードを閉じます")
            hideKeyboard()
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
