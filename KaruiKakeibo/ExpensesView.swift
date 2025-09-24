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
    @FocusState private var isSearchFocused: Bool

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
                let matchesDate = matchesDateSearch(expense: expense, searchText: searchText)
                
                return matchesNote || matchesCategory || matchesAmount || matchesDate
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
    
    // 日付検索のマッチング関数
    private func matchesDateSearch(expense: Expense, searchText: String) -> Bool {
        let expenseDate = expense.date
        
        // 日付フォーマット候補
        let dateFormatters = [
            "yyyy/M/d",     // 2024/1/15
            "yyyy/MM/dd",   // 2024/01/15
            "M/d",          // 1/15
            "MM/dd",        // 01/15
            "M月d日",       // 1月15日
            "MM月dd日",     // 01月15日
            "M月",          // 1月
            "MM月",         // 01月
            "yyyy年",       // 2024年
            "yyyy年M月",    // 2024年1月
            "yyyy年MM月",   // 2024年01月
            "yyyy年M月d日", // 2024年1月15日
            "HH:mm",        // 14:30
            "H:mm",         // 9:30
            "d日",          // 15日
            "dd日"          // 15日
        ]
        
        // 各フォーマットで検索テキストと照合
        for formatString in dateFormatters {
            let formatter = DateFormatter()
            formatter.dateFormat = formatString
            formatter.locale = Locale(identifier: "ja_JP")
            
            let expenseDateString = formatter.string(from: expenseDate)
            
            // 部分一致で検索
            if expenseDateString.localizedCaseInsensitiveContains(searchText) {
                return true
            }
        }
        
        // 曜日での検索（日本語）
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEEE"  // 月曜日、火曜日など
        weekdayFormatter.locale = Locale(identifier: "ja_JP")
        let weekdayFull = weekdayFormatter.string(from: expenseDate)
        
        weekdayFormatter.dateFormat = "E"     // 月、火など
        let weekdayShort = weekdayFormatter.string(from: expenseDate)
        
        if weekdayFull.localizedCaseInsensitiveContains(searchText) ||
           weekdayShort.localizedCaseInsensitiveContains(searchText) {
            return true
        }
        
        // 「今日」「昨日」「一昨日」での検索
        let calendar = Calendar.current
        let today = Date()
        
        if searchText.contains("今日") || searchText.contains("きょう") {
            return calendar.isDate(expenseDate, inSameDayAs: today)
        }
        
        if searchText.contains("昨日") || searchText.contains("きのう") {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
                return calendar.isDate(expenseDate, inSameDayAs: yesterday)
            }
        }
        
        if searchText.contains("一昨日") || searchText.contains("おととい") {
            if let dayBeforeYesterday = calendar.date(byAdding: .day, value: -2, to: today) {
                return calendar.isDate(expenseDate, inSameDayAs: dayBeforeYesterday)
            }
        }
        
        // 「今週」「先週」「今月」「先月」での検索
        if searchText.contains("今週") {
            return calendar.isDate(expenseDate, equalTo: today, toGranularity: .weekOfYear)
        }
        
        if searchText.contains("先週") {
            if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: today) {
                return calendar.isDate(expenseDate, equalTo: lastWeek, toGranularity: .weekOfYear)
            }
        }
        
        if searchText.contains("今月") {
            return calendar.isDate(expenseDate, equalTo: today, toGranularity: .month)
        }
        
        if searchText.contains("先月") {
            if let lastMonth = calendar.date(byAdding: .month, value: -1, to: today) {
                return calendar.isDate(expenseDate, equalTo: lastMonth, toGranularity: .month)
            }
        }
        
        return false
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
        return "メモ、カテゴリ、金額、日付で検索"
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
    
    // 日付検索かどうかを判定
    private func isDateSearch(_ text: String) -> Bool {
        // 日付関連のキーワードをチェック
        let dateKeywords = [
            "今日", "昨日", "一昨日", "おととい", "きょう", "きのう",
            "今週", "先週", "今月", "先月",
            "月", "日", "年", "時", "分",
            "月曜", "火曜", "水曜", "木曜", "金曜", "土曜", "日曜",
            "月", "火", "水", "木", "金", "土", "日"
        ]
        
        for keyword in dateKeywords {
            if text.contains(keyword) {
                return true
            }
        }
        
        // 数字とスラッシュ、コロンを含む場合（日付フォーマットの可能性）
        let datePattern = #"^\d{1,4}[/年月日時分:]\d{0,2}[/月日時分:]?\d{0,2}[日時分:]?\d{0,2}[分:]?$"#
        return text.range(of: datePattern, options: .regularExpression) != nil
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 検索ヒント表示（検索中のみ）
                if !searchText.isEmpty {
                    SearchHintView(
                        searchText: searchText,
                        isNumericSearch: isNumericSearch(searchText),
                        isDateSearch: isDateSearch(searchText),
                        resultCount: filteredExpenses.count
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                List {
                    if !filteredExpenses.isEmpty {
                        ExpenseSummaryHeaderView(
                            totalAmount: totalAmount,
                            expenseCount: filteredExpenses.count,
                            searchText: searchText
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(searchText.isEmpty ?
                            "合計支出 \(Int(totalAmount))円、\(expenseCountText)" :
                            "検索結果: 合計 \(Int(totalAmount))円、\(expenseCountText)"
                        )
                        .accessibilityHint("支出の概要情報")
                    }
                    
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
                                highlightAmount: isNumericSearch(searchText),
                                highlightDate: isDateSearch(searchText)
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
                            isNumericSearch: isNumericSearch(searchText),
                            isDateSearch: isDateSearch(searchText)
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
            .safeAreaInset(edge: .bottom) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField(searchPrompt, text: $searchText)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .submitLabel(.search)
                                .focused($isSearchFocused)
                        }
                        .padding(12)
                        .background(
                            Group {
                                if #available(iOS 26.0, *) {
                                    Color.clear
                                        .glassEffect(
                                            .regular
//                                                .tint(.blue.opacity(0.35))
                                                .interactive(),
                                            in: .capsule
                                        )
                                } else {
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                                        )
                                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
                                }
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
            }
            // 🎯 iOS 18未満では代替手段として検索テキストの強制更新を使用
            .onChange(of: searchFieldTrigger) { _, _ in
                // 検索フィールドにフォーカスを当てるための代替手段
                focusSearchFieldFallback()
            }
//            // 🎹 キーボード用ツールバー
//            .toolbar {
//                ToolbarItemGroup(placement: .keyboard) {
//                    Button("閉じる") {
//                        hideKeyboard()
//                    }
//                    .foregroundColor(.blue)
//                    .fontWeight(.semibold)
//                }
//            }
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
        
        DispatchQueue.main.async {
            self.isSearchFocused = true
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
    let isDateSearch: Bool
    let resultCount: Int
    
    private var hintIcon: String {
        if isDateSearch {
            return "calendar"
        } else if isNumericSearch {
            return "yensign.circle"
        } else {
            return "magnifyingglass"
        }
    }
    
    private var hintColor: Color {
        if isDateSearch {
            return .orange
        } else if isNumericSearch {
            return .green
        } else {
            return .blue
        }
    }
    
    private var hintText: String {
        if isDateSearch {
            return "日付「\(searchText)」で検索中 - \(resultCount)件見つかりました"
        } else if isNumericSearch {
            return "金額「\(searchText)」で検索中 - \(resultCount)件見つかりました"
        } else {
            return "「\(searchText)」で検索中 - \(resultCount)件見つかりました"
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: hintIcon)
                .foregroundColor(hintColor)
                .font(.caption)
            
            Text(hintText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hintColor.opacity(0.1))
                .stroke(hintColor.opacity(0.3), lineWidth: 1)
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
    let isDateSearch: Bool
    
    private var emptyStateIcon: String {
        if isDateSearch {
            return "calendar"
        } else if isNumericSearch {
            return "yensign.circle"
        } else {
            return "magnifyingglass"
        }
    }
    
    private var emptyStateTitle: String {
        if isDateSearch {
            return "日付「\(searchText)」の検索結果がありません"
        } else if isNumericSearch {
            return "金額「\(searchText)」の検索結果がありません"
        } else {
            return "「\(searchText)」の検索結果がありません"
        }
    }
    
    private var emptyStateDescription: String {
        if isDateSearch {
            return "日付形式の例：\n• 2024/1/15\n• 1月15日\n• 今日、昨日\n• 今月、先月\n• 月曜日、火曜日"
        } else if isNumericSearch {
            return "金額の部分一致で検索しています。例：「500」で「1500円」もヒットします"
        } else {
            return "メモ、カテゴリ名、金額、または日付で検索してみてください"
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 60))
                .foregroundColor(.gray)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text(emptyStateTitle)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
                
                Text(emptyStateDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityHidden(true)
                
                if !isDateSearch && !isNumericSearch {
                    Text("別のキーワードで検索してみてください")
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
    let highlightDate: Bool
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
                    
                    // 修正: 日時表示を統一フォーマットに変更（日付検索時はハイライト）
                    Text("\(expense.date, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(highlightDate ? .orange : .secondary)
                        .background(
                            highlightDate ?
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.orange.opacity(0.2))
                                .padding(.horizontal, -4)
                                .padding(.vertical, -2) :
                            nil
                        )
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

