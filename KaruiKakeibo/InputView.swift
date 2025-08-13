//
//  InputView.swift (時刻選択対応版)
//  Suguni-Kakeibo-2
//
//  Created by 大谷駿介 on 2025/07/29.
//

import SwiftUI

struct InputView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Binding var shouldFocusAmount: Bool
    @State private var amount: String = ""
    @State private var date = Date()
    @State private var note: String = ""
    @State private var selectedCategoryId: Int = 1
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showSuccessMessage = false
    @State private var isProcessing = false
    @State private var showDoubleTapHint = false
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var isAmountFocused: Bool
    @FocusState private var isNoteFocused: Bool
    
    // 設定値を読み込み
    @AppStorage("autoFocusAfterSave") private var autoFocusAfterSave = true

    // デフォルト初期化子を追加
    init(shouldFocusAmount: Binding<Bool> = .constant(false)) {
        self._shouldFocusAmount = shouldFocusAmount
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("金額 (画面を2回タップでフォーカスできます)")) {
                    HStack {
                        Text("¥")
                            .foregroundColor(.secondary)
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.title2)
                            .fontWeight(.medium)
                            .focused($isAmountFocused)
                            .onChange(of: amount) { _, newValue in
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
                
                Section(header: Text("カテゴリ")) {
                    // カテゴリピッカーを独立したセクションに
                    CategoryPickerView(
                        selectedCategoryId: $selectedCategoryId
                    )
                    .environmentObject(viewModel) // ViewModelを渡す
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                
                Section(header: Text("メモ（任意）")) {
                    TextField("メモを入力", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($isNoteFocused)
                        .onChange(of: note) { _, newValue in
                            // メモの文字数制限（100文字）
                            if newValue.count > 100 {
                                note = String(newValue.prefix(100))
                            }
                        }
                }
                
                // 設定が有効な場合のみダブルタップヒントを表示
                if showDoubleTapHint && autoFocusAfterSave {
                    Section {
                        HStack {
                            Image(systemName: "hand.tap.fill")
                                .foregroundColor(.blue)
                            Text("画面をダブルタップで金額入力に戻れます")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(Color.blue.opacity(0.05))
                    }
                    .transition(.opacity.combined(with: .scale))
                }
                
                // 自動フォーカス設定の案内
                if autoFocusAfterSave {
                    Section {
                        HStack {
                            Image(systemName: "gear")
                                .foregroundColor(.gray)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("保存後に自動で金額入力にフォーカスがONです")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("設定画面で変更できます")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .listRowBackground(Color.gray.opacity(0.05))
                    }
                    .transition(.opacity)
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
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("支出入力")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("クリア") {
                        clearFields()
                    }
                    .foregroundColor(.orange)
                    .disabled(isProcessing)
                }
                
                ToolbarItemGroup(placement: .keyboard) {
                    // 金額入力用のツールバー
                    HStack {
                        if isAmountFocused {
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
                        Spacer()
                    }
                    .frame(minHeight: 32)   // 最小の高さを確保
                    
                    Button("完了") {
                        hideKeyboard()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.semibold)
                }
            }
            // フロートボタンを追加
            .safeAreaInset(edge: .bottom) {
                FloatingActionButton(
                    isButtonEnabled: isButtonEnabled,
                    isProcessing: isProcessing,
                    keyboardHeight: keyboardHeight,
                    action: saveExpense,
                    doubleTapAction: {
                        focusAmountFieldForManualTap()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("入力エラー"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .overlay(
                // 成功メッセージ
                VStack {
                    if showSuccessMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("支出を保存しました")
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(Color.green.opacity(0.9))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .transition(.scale.combined(with: .opacity))
                        .shadow(radius: 4)
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            )
            // 修正: 背景タップでキーボードを閉じる
            .contentShape(Rectangle())
            .simultaneousGesture(
                // シングルタップ：キーボードを閉じる（フィールドにフォーカス中のみ）
                TapGesture(count: 1)
                    .onEnded { _ in
                        if isAmountFocused || isNoteFocused {
                            hideKeyboard()
                        }
                    }
            )
            .simultaneousGesture(
                // ダブルタップ：金額フィールドにフォーカス
                TapGesture(count: 2)
                    .onEnded { _ in
                        if !isAmountFocused {
                            focusAmountFieldForManualTap()
                        }
                    }
            )
            .onAppear {
                setupInitialCategory()
                showDoubleTapHintIfNeeded()
                setupKeyboardObservers()
            }
            .onChange(of: shouldFocusAmount) { _, newValue in
                // 外部からのフォーカス要求を処理
                if newValue {
                    focusAmountField()
                    shouldFocusAmount = false
                }
            }
        }
    }
    
    // MARK: - 計算プロパティを分離してコンパイラエラーを解決
    private var isButtonEnabled: Bool {
        let hasAmount = !amount.isEmpty
        let isValidAmountValue = isValidAmount(amount)
        let hasVisibleCategories = !viewModel.getVisibleCategories().isEmpty
        let notProcessing = !isProcessing
        
        return hasAmount && isValidAmountValue && hasVisibleCategories && notProcessing
    }
    
    // MARK: - キーボード監視の設定
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeOut(duration: 0.3)) {
                    keyboardHeight = keyboardFrame.height
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                keyboardHeight = 0
            }
        }
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
    
    // 手動タップ用のフォーカス関数（設定に関係なく常に動作）
    private func focusAmountFieldForManualTap() {
        // 既に金額フィールドにフォーカスしている場合は何もしない
        guard !isAmountFocused else { return }
        
        // キーボードを一旦閉じてから金額入力にフォーカス
        isNoteFocused = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isAmountFocused = true
            
            // ハプティックフィードバック
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            print("💰 手動ダブルタップで金額入力フィールドにフォーカス")
        }
    }

    // 自動フォーカス用の関数（設定に依存）
    private func focusAmountField() {
        // 設定で無効になっている場合は何もしない
        guard autoFocusAfterSave else { return }
        
        focusAmountFieldForManualTap()
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
    
    private func setupInitialCategory() {
        // 可視カテゴリの最初のものを選択
        let visibleCategories = viewModel.getVisibleCategories()
        if selectedCategoryId == 1 && !visibleCategories.isEmpty {
            selectedCategoryId = visibleCategories.first?.id ?? 1
        }
    }
    
    private func showDoubleTapHintIfNeeded() {
        // 自動フォーカス設定が有効な場合のみヒントを表示
        guard autoFocusAfterSave else { return }
        
        // 最初の3回のアプリ起動時にヒントを表示
        let hintShownKey = "doubleTapHintShown"
        let hintCount = UserDefaults.standard.integer(forKey: hintShownKey)
        
        if hintCount < 3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.spring(response: 0.5)) {
                    showDoubleTapHint = true
                }
                
                // 5秒後に自動で非表示
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    withAnimation(.spring(response: 0.5)) {
                        showDoubleTapHint = false
                    }
                }
            }
            
            UserDefaults.standard.set(hintCount + 1, forKey: hintShownKey)
        }
    }
    
    private func hideKeyboard() {
        isAmountFocused = false
        isNoteFocused = false
    }
    
    private func saveExpense() {
        guard !isProcessing else { return }
        
        // 支出を保存ボタンを押した時のHapticフィードバック
        let lightImpact = UIImpactFeedbackGenerator(style: .light)
        lightImpact.impactOccurred()
        
        hideKeyboard()
        
        // より厳密な金額バリデーション
        guard !amount.isEmpty else {
            let errorFeedback = UINotificationFeedbackGenerator()
            errorFeedback.notificationOccurred(.error)
            alertMessage = "金額を入力してください。"
            showAlert = true
            return
        }
        
        guard let parsedAmount = Double(amount) else {
            let errorFeedback = UINotificationFeedbackGenerator()
            errorFeedback.notificationOccurred(.error)
            alertMessage = "金額は数値で入力してください。"
            showAlert = true
            return
        }
        
        guard parsedAmount > 0 else {
            let errorFeedback = UINotificationFeedbackGenerator()
            errorFeedback.notificationOccurred(.error)
            alertMessage = "金額は0円より大きい値を入力してください。"
            showAlert = true
            return
        }
        
        guard parsedAmount <= 99999999999 else {
            let errorFeedback = UINotificationFeedbackGenerator()
            errorFeedback.notificationOccurred(.error)
            alertMessage = "金額は999億円以下で入力してください。"
            showAlert = true
            return
        }

        // 可視カテゴリのチェック
        let visibleCategories = viewModel.getVisibleCategories()
        guard visibleCategories.contains(where: { $0.id == selectedCategoryId }) else {
            let errorFeedback = UINotificationFeedbackGenerator()
            errorFeedback.notificationOccurred(.error)
            alertMessage = "選択されたカテゴリが表示設定されていません。カテゴリを再選択してください。"
            showAlert = true
            return
        }
        
        // 未来の日付をチェック
        if date > Date() {
            let errorFeedback = UINotificationFeedbackGenerator()
            errorFeedback.notificationOccurred(.error)
            alertMessage = "未来の日時は設定できません。"
            showAlert = true
            return
        }
        
        // 処理開始時にmediumフィードバック
        let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
        mediumImpact.impactOccurred()

        isProcessing = true
        
        let expense = Expense(
            id: 0,
            amount: parsedAmount,
            date: date,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryId: selectedCategoryId,
            userId: 1
        )
        
        // 保存処理
        viewModel.addExpense(expense)
        
        // 成功時に成功フィードバック
        let successFeedback = UINotificationFeedbackGenerator()
        successFeedback.notificationOccurred(.success)
        
        // 成功メッセージを表示
        withAnimation(.spring(response: 0.3)) {
            showSuccessMessage = true
        }
        
        // フィールドをリセット
        clearFields()
        
        // 処理完了
        isProcessing = false
        
        // 成功メッセージを非表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.spring(response: 0.3)) {
                showSuccessMessage = false
            }
        }
        
        // 設定に応じて金額フィールドにフォーカスを戻す
        if autoFocusAfterSave {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isAmountFocused = true
                print("⚙️ 自動フォーカス設定により金額入力にフォーカス")
            }
        } else {
            print("⚙️ 自動フォーカス設定がOFFのため、フォーカスを移動しません")
        }
    }
    
    private func clearFields() {
        amount = ""
        note = ""
        date = Date()
        
        // 可視カテゴリの最初のものを再選択
        let visibleCategories = viewModel.getVisibleCategories()
        if let first = visibleCategories.first {
            selectedCategoryId = first.id
        }
    }
}

// MARK: - フロートアクションボタン

struct FloatingActionButton: View {
    let isButtonEnabled: Bool
    let isProcessing: Bool
    let keyboardHeight: CGFloat
    let action: () -> Void
    let doubleTapAction: () -> Void
    
    @AppStorage("autoFocusAfterSave") private var autoFocusAfterSave = true
    
    var buttonColor: Color {
        if isProcessing { return .orange }
        if isButtonEnabled { return .blue }
        return .gray
    }
    
    var buttonText: String {
        if isProcessing { return "保存中..." }
        if isButtonEnabled { return "支出を保存" }
        return "入力を完了してください"
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.prepare()
                impactFeedback.impactOccurred()
                
                action()
            }) {
                HStack(spacing: 12) {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                        Text(buttonText)
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: isButtonEnabled ? "plus.circle.fill" : "exclamationmark.circle")
                            .font(.title3)
                        Text(buttonText)
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [buttonColor, buttonColor.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(
                            color: isButtonEnabled ? buttonColor.opacity(0.4) : Color.clear,
                            radius: 8,
                            x: 0,
                            y: 4
                        )
                )
            }
            .disabled(!isButtonEnabled || isProcessing)
            .buttonStyle(FloatingButtonStyle())
            .scaleEffect(isProcessing ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isProcessing)
            .animation(.easeInOut(duration: 0.3), value: isButtonEnabled)
        }
    }
}

// MARK: - フロートボタン用のカスタムスタイル

struct FloatingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 既存のコンポーネント（変更なし）

// カテゴリ情報構造体（Equatable対応）
struct CategoryInfo: Identifiable, Equatable {
    let id: Int
    let name: String
    
    static func == (lhs: CategoryInfo, rhs: CategoryInfo) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name
    }
}

// カテゴリピッカーを独立したビューに（修正版）
struct CategoryPickerView: View {
    @Binding var selectedCategoryId: Int
    @EnvironmentObject var viewModel: ExpenseViewModel
    
    // 表示するカテゴリを可視カテゴリに限定（Equatable対応）
    private var displayCategories: [CategoryInfo] {
        return viewModel.getVisibleCategories().map { CategoryInfo(id: $0.id, name: $0.name) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // カテゴリが存在しない場合の警告
            if displayCategories.isEmpty {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("表示可能なカテゴリがありません")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                    
                    Text("設定画面からカテゴリを追加するか、既存カテゴリの表示設定を確認してください。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.1))
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            } else {
                // カテゴリボタンのグリッド表示
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                    ForEach(displayCategories) { category in
                        CategoryButtonView(
                            category: category,
                            isSelected: selectedCategoryId == category.id,
                            action: {
                                selectedCategoryId = category.id
                                
                                // ハプティックフィードバック
                                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                impactFeedback.impactOccurred()
                            }
                        )
                        .environmentObject(viewModel) // ViewModelを渡す
                    }
                }
                
                // 現在選択されているカテゴリを表示
                if let currentCategory = displayCategories.first(where: { $0.id == selectedCategoryId }) {
                    HStack {
                        Image(systemName: "tag.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("選択中: \(currentCategory.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                    .animation(.easeInOut(duration: 0.2), value: selectedCategoryId)
                } else if !displayCategories.isEmpty {
                    // 選択されたカテゴリが表示リストにない場合、最初のカテゴリを自動選択
                    Text("カテゴリを選択してください")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .onAppear {
                            if let first = displayCategories.first {
                                selectedCategoryId = first.id
                            }
                        }
                }
            }
        }
        .padding()
        .onChange(of: displayCategories) { _, newCategories in
            // カテゴリが変更された場合の処理
            if !newCategories.contains(where: { $0.id == selectedCategoryId }) {
                // 現在選択されているカテゴリが表示リストにない場合、最初のカテゴリを選択
                if let first = newCategories.first {
                    selectedCategoryId = first.id
                }
            }
        }
    }
}

// カテゴリボタンのビュー（修正版）
struct CategoryButtonView: View {
    let category: CategoryInfo
    let isSelected: Bool
    let action: () -> Void
    @EnvironmentObject var viewModel: ExpenseViewModel
    
    // データベースから動的にアイコンを取得
    private var categoryIcon: String {
        return viewModel.categoryIcon(for: category.id)
    }
    
    // データベースから動的に色を取得
    private var categoryColor: Color {
        let colorString = viewModel.categoryColor(for: category.id)
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
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: categoryIcon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? categoryColor : Color.gray.opacity(0.6))
                    .clipShape(Circle())
                
                Text(category.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? categoryColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? categoryColor.opacity(0.1) : Color.gray.opacity(0.05))
                    .stroke(isSelected ? categoryColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct InputView_Previews: PreviewProvider {
    static var previews: some View {
        InputView()
            .environmentObject(ExpenseViewModel())
    }
}
