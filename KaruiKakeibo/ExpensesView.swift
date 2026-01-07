import SwiftUI
import Foundation

struct ExpensesView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @State private var searchText = ""
    @State private var selectedExpenseId: Int? = nil
    @State private var showingDeleteConfirmation = false
    @State private var expenseToDelete: Expense?
    @Environment(\.accessibilityVoiceOverEnabled) var voiceOverEnabled
    
    // タブ再選択によるフォーカス制御用（iOS 18未満では代替手段を使用）
    @State private var searchFieldTrigger = false
    // キーボード表示状態管理
    @State private var isKeyboardVisible = false
    @FocusState private var isSearchFocused: Bool
    @State private var listRefreshID = UUID()

    // 静的キャッシュ（型チェックと実行コストの削減）
    private static let dateKeywordSet: Set<String> = [
        "今日", "昨日", "一昨日", "おととい", "きょう", "きのう",
        "今週", "先週", "今月", "先月",
        "月", "日", "年", "時", "分",
        "月曜", "火曜", "水曜", "木曜", "金曜", "土曜", "日曜",
        "月", "火", "水", "木", "金", "土", "日"
    ]
    private static let datePattern: String = #"^\d{1,4}[/年月日時分:]\d{0,2}[/月日時分:]?\d{0,2}[日時分:]?\d{0,2}[分:]?$"#
    private static let dateRegex: NSRegularExpression = {
        // パターンの事前コンパイル
        // 失敗時はワイルドカードにフォールバック
        return (try? NSRegularExpression(pattern: ExpensesView.datePattern)) ?? NSRegularExpression()
    }()
    
    // 日付フォーマッタを静的にキャッシュ
    private static let dateFormatStrings: [String] = [
        "yyyy/M/d", "yyyy/MM/dd", "M/d", "MM/dd",
        "M月d日", "MM月dd日", "M月", "MM月",
        "yyyy年", "yyyy年M月", "yyyy年MM月", "yyyy年M月d日",
        "HH:mm", "H:mm", "d日", "dd日"
    ]
    private static let cachedDateFormatters: [DateFormatter] = {
        let locale = Locale(identifier: "ja_JP")
        return dateFormatStrings.map { format in
            let f = DateFormatter()
            f.dateFormat = format
            f.locale = locale
            return f
        }
    }()
    private static let weekdayFullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()
    private static let weekdayShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E"
        f.locale = Locale(identifier: "ja_JP")
        return f
    }()
    
    // MARK: - Precomputed View State to reduce type-checking load
    private var numericSearchActive: Bool { isNumericSearch(searchText) }
    private var dateSearchActive: Bool { isDateSearch(searchText) }
    private var currentFilteredExpenses: [Expense] { computeFilteredExpenses() }
    private var hasSearchText: Bool { !searchText.isEmpty }
    private var totalAmountForFiltered: Double { computeTotalAmount(for: currentFilteredExpenses) }
    private var expenseCountForFiltered: Int { currentFilteredExpenses.count }
    private var summaryAccessibilityLabelComputed: String {
        if hasSearchText {
            return "検索結果: 合計 \(Int(totalAmountForFiltered))円、\(makeExpenseCountText(expenseCountForFiltered))"
        } else {
            return "合計支出 \(Int(totalAmountForFiltered))円、\(makeExpenseCountText(expenseCountForFiltered))"
        }
    }
    private var showSearchEmptyState: Bool { currentFilteredExpenses.isEmpty && hasSearchText }
    private var showGeneralEmptyState: Bool { viewModel.expenses.isEmpty }
    
    // フィルタ済み支出の計算（関数化して型推論負荷を軽減）
    private func computeFilteredExpenses() -> [Expense] {
        let expenses = viewModel.expenses.sorted(by: { $0.date > $1.date })
        guard !searchText.isEmpty else { return expenses }
        return expenses.filter { expense in
            let note = expense.note
            let categoryName = viewModel.categories.first(where: { $0.id == expense.categoryId })?.name ?? ""
            let matchesNote = note.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = categoryName.localizedCaseInsensitiveContains(searchText)
            let matchesAmount = matchesAmountSearch(expense: expense, searchText: searchText)
            let matchesDate = matchesDateSearch(expense: expense, searchText: searchText)
            return matchesNote || matchesCategory || matchesAmount || matchesDate
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

        // 各フォーマットで検索テキストと照合（キャッシュ使用）
        for formatter in ExpensesView.cachedDateFormatters {
            let expenseDateString = formatter.string(from: expenseDate)
            if expenseDateString.localizedCaseInsensitiveContains(searchText) {
                return true
            }
        }

        // 曜日での検索（日本語） - キャッシュ使用
        let weekdayFull = ExpensesView.weekdayFullFormatter.string(from: expenseDate)
        let weekdayShort = ExpensesView.weekdayShortFormatter.string(from: expenseDate)
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
    
    // 日付検索かどうかを判定
    private func isDateSearch(_ text: String) -> Bool {
        // 早期リターン: 空文字は日付検索ではない
        if text.isEmpty { return false }

        // キーワードマッチ（軽量）
        for keyword in ExpensesView.dateKeywordSet {
            if text.contains(keyword) {
                return true
            }
        }

        // 数字とスラッシュ、コロンを含む場合（日付フォーマットの可能性）
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return ExpensesView.dateRegex.firstMatch(in: text, options: [], range: range) != nil
    }
    
    private func computeTotalAmount(for expenses: [Expense]) -> Double {
        expenses.reduce(0) { $0 + $1.amount }
    }
    
    private func makeExpenseCountText(_ count: Int) -> String {
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
    
    // MARK: - Background helper to reduce builder complexity
    @ViewBuilder
    private func keyboardDismissBackground(isKeyboardVisible: Bool) -> some View {
        if isKeyboardVisible {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { hideKeyboard() }
                .allowsHitTesting(true)
        } else {
            Color.clear
                .allowsHitTesting(false)
        }
    }

    // MARK: - Overlay / Sheet helpers to reduce type-check load
    @ViewBuilder
    private var emptyStateOverlay: some View {
        if showSearchEmptyState {
            SearchEmptyStateView(
                searchText: searchText,
                isNumericSearch: numericSearchActive,
                isDateSearch: dateSearchActive
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("検索結果なし。\(searchText)に一致する支出が見つかりません！")
            .accessibilityHint("別のキーワードで検索？")
        } else if showGeneralEmptyState {
            GeneralEmptyStateView()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("支出履歴なし")
                .accessibilityHint("入力タブから支出を追加")
        }
    }

    private var expenseSheetItem: Binding<ExpenseSheetItem?> {
        Binding(
            get: {
                selectedExpenseId.map { ExpenseSheetItem(id: $0) }
            },
            set: { _ in
                selectedExpenseId = nil
            }
        )
    }

    private func refreshAfterEdit() {
        // 編集後に最新データを反映
        viewModel.refreshAllData()
        listRefreshID = UUID()
    }

    @ViewBuilder
    private var screenContent: some View {
        VStack(spacing: 0) {
            // 検索ヒント表示（検索中のみ）
            if hasSearchText {
                SearchHintView(
                    searchText: searchText,
                    isNumericSearch: numericSearchActive,
                    isDateSearch: dateSearchActive,
                    resultCount: currentFilteredExpenses.count
                )
                .padding(.horizontal)
                .padding(.bottom, 8)
            }

            ExpensesListSection(
                filtered: currentFilteredExpenses,
                totalAmount: totalAmountForFiltered,
                searchText: searchText,
                expenseCountText: makeExpenseCountText(expenseCountForFiltered),
                numericSearch: numericSearchActive,
                dateSearch: dateSearchActive,
                isKeyboardVisible: $isKeyboardVisible,
                selectedExpenseId: $selectedExpenseId
            )
            .environmentObject(viewModel)
            .id(listRefreshID)
            .scrollDismissesKeyboard(.immediately) // 🎹 スクロール時にキーボードを閉じる
            .overlay { emptyStateOverlay }
        }
        .navigationTitle("支出履歴")
        .navigationBarTitleDisplayMode(.automatic)
        .safeAreaInset(edge: .bottom) {
            SearchBarInset(searchText: $searchText, isSearchFocused: _isSearchFocused, prompt: searchPrompt)
        }
        // 🎯 iOS 18未満では代替手段として検索テキストの強制更新を使用
        .onChange(of: searchFieldTrigger) { _, _ in
            // 検索フィールドにフォーカスを当てるための代替手段
            focusSearchFieldFallback()
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
            keyboardDismissBackground(isKeyboardVisible: isKeyboardVisible)
        )
        .accessibilityAction(.escape) {
            if !searchText.isEmpty {
                searchText = ""
            }
        }
        .refreshable {
            viewModel.refreshAllData()
            listRefreshID = UUID()
        }
        .onChange(of: viewModel.expenses) { _, _ in
            // データ変更時にリストを再構築
            listRefreshID = UUID()
        }
    }
    
    var body: some View {
        NavigationStack {
            screenContent
        }
        .sheet(item: expenseSheetItem, onDismiss: refreshAfterEdit) { item in
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
        .onAppear {
            viewModel.refreshAllData()
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
    
    // iOS 18未満での検索フィールドフォーカス代替手段
    private func focusSearchFieldFallback() {
        print("focusSearchFieldFallback() 実行")
        
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
                print("UISearchBarにフォーカス設定完了")
                return
            } else if let textField = subview as? UITextField,
                      subview.accessibilityIdentifier?.contains("search") == true ||
                      textField.placeholder?.contains("検索") == true {
                textField.becomeFirstResponder()
                print("UITextFieldにフォーカス設定完了")
                return
            }
            
            // 再帰的に子ビューを探索
            findAndFocusSearchBar(in: subview)
        }
    }
    
    // MARK: - キーボード管理
    
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
            print("キーボード表示 - ツールバー表示")
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
        print("キーボード監視解除")
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
        
        print("キーボードを手動で閉じました")
    }
    
    // スクロール開始時の追加処理（必要に応じて）
    private func handleScrollBegan() {
        // スクロール開始時にキーボードを閉じる（.scrollDismissesKeyboardと併用）
        if isKeyboardVisible {
            print("スクロール開始によりキーボードを閉じます")
            hideKeyboard()
        }
    }
    
    // MARK: - アクセシビリティヘルパー
    private func createExpenseAccessibilityLabel(for expense: Expense) -> String {
        let categoryName = viewModel.categoryName(for: expense.categoryId)
        let dateFormatter: DateFormatter = DateFormatter()
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
                let current = computeFilteredExpenses()
                let expense = current[index]
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
                Text("支出履歴なし")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                
                Text("「入力」タブから支出を追加")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding()
    }
}

// リストセクションを分割して型推論負荷を軽減
private struct ExpensesListSection: View {
    let filtered: [Expense]
    let totalAmount: Double
    let searchText: String
    let expenseCountText: String
    let numericSearch: Bool
    let dateSearch: Bool
    @Binding var isKeyboardVisible: Bool
    @Binding var selectedExpenseId: Int?
    @EnvironmentObject var viewModel: ExpenseViewModel

    private var summaryLabel: String {
        if searchText.isEmpty {
            return "合計支出 \(Int(totalAmount))円、\(expenseCountText)"
        } else {
            return "検索結果: 合計 \(Int(totalAmount))円、\(expenseCountText)"
        }
    }

    var body: some View {
        List {
            if !filtered.isEmpty {
                ExpenseSummaryHeaderView(
                    totalAmount: totalAmount,
                    expenseCount: filtered.count,
                    searchText: searchText
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(summaryLabel)
                .accessibilityHint("支出の概要情報")
            }

            ForEach(filtered) { expense in
                Button(action: {
                    if !isKeyboardVisible {
                        selectedExpenseId = expense.id
                    }
                }) {
                    ExpenseRowView(
                        expense: expense,
                        viewModel: viewModel,
                        searchText: searchText,
                        highlightAmount: numericSearch,
                        highlightDate: dateSearch
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
                    viewModel.deleteExpense(id: expense.id)
                }
                .disabled(isKeyboardVisible)
            }
            .onDelete { offsets in
                withAnimation(.easeInOut(duration: 0.3)) {
                    for index in offsets {
                        let expense = filtered[index]
                        viewModel.deleteExpense(id: expense.id)
                    }
                }
            }
        }
        .listStyle(.plain)
        .accessibilityLabel("支出履歴一覧")
    }

    // MARK: - アクセシビリティヘルパー（ローカルに複製）
    private func createExpenseAccessibilityLabel(for expense: Expense) -> String {
        let categoryName = viewModel.categoryName(for: expense.categoryId)
        let dateFormatter: DateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.locale = Locale(identifier: "ja_JP")
        let dateString = dateFormatter.string(from: expense.date)
        var label = "\(Int(expense.amount))円、\(categoryName)、\(dateString)"
        if !expense.note.isEmpty { label += "、メモ: \(expense.note)" }
        return label
    }
}

// 検索バーインセットを分割
private struct SearchBarInset: View {
    @Binding var searchText: String
    @FocusState var isSearchFocused: Bool
    let prompt: String
    
    @ViewBuilder
    private var searchBarBackground: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(
                    .regular
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
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(prompt, text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .focused($isSearchFocused)
        }
        .padding(12)
        .background(searchBarBackground)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
    
    private var signedAmountText: String {
        let prefix = expense.type == .income ? "+" : "-"
        return "\(prefix)¥\(String(format: "%.0f", expense.amount))"
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
    
    // MARK: - Highlight helpers to simplify view builder expressions
    private var amountTextColor: Color {
        if highlightAmount { return .green }
        return expense.type == .income ? .green : .primary
    }

    @ViewBuilder
    private var amountHighlightBackground: some View {
        if highlightAmount {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.green.opacity(0.2))
                .padding(.horizontal, -4)
                .padding(.vertical, -2)
        } else {
            EmptyView()
        }
    }

    private var dateTextColor: Color {
        highlightDate ? .orange : .secondary
    }

    @ViewBuilder
    private var dateHighlightBackground: some View {
        if highlightDate {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.orange.opacity(0.2))
                .padding(.horizontal, -4)
                .padding(.vertical, -2)
        } else {
            EmptyView()
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
                    Text(signedAmountText)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(amountTextColor)
                        .background(amountHighlightBackground)
                        .accessibilityHidden(true)
                    
                    Spacer()
                    
                    // 修正: 日時表示を統一フォーマットに変更（日付検索時はハイライト）
                    Text("\(expense.date, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(dateTextColor)
                        .background(dateHighlightBackground)
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

