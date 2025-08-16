//
//  SettingView.swift (レスポンス改善版)
//  Suguni-Kakeibo-2
//
//  Created by 大谷駿介 on 2025/07/29.
//

import SwiftUI

struct SettingView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
//    @AppStorage("currency") private var currency = "円"
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("autoFocusAfterSave") private var autoFocusAfterSave = false
    @State private var showingExportView = false
    @State private var showingCategoryManagement = false
    @State private var showingResetCategoriesAlert = false
    @State private var showingResetSettingsAlert = false
    @State private var isResetingCategories = false
//    @FocusState private var isCurrencyFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("便利機能")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("保存後に自動で金額入力にフォーカス", isOn: $autoFocusAfterSave)
                        
                        Text("支出保存後、続けて入力する際に金額フィールドに自動でカーソルを移動する機能です")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                
//                Section(header: Text("通貨設定")) {
//                    TextField("通貨単位", text: $currency)
//                        .focused($isCurrencyFocused)
//                }
                
                // カテゴリ管理セクション（改善版）
                Section(header: Text("カテゴリ管理")) {
                    // カテゴリ編集ボタン（改善版）
                    Button(action: {
                        // ハプティックフィードバックを追加
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        showingCategoryManagement = true
                    }) {
                        CategoryManagementButtonView(
                            icon: "tag.circle",
                            title: "カテゴリの編集",
                            subtitle: "カテゴリの追加・編集・表示設定",
                            color: .orange
                        )
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    
                    // デフォルトカテゴリリセットボタン（改善版）
                    Button(action: {
                        // ハプティックフィードバックを追加
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        showingResetCategoriesAlert = true
                    }) {
                        CategoryManagementButtonView(
                            icon: "arrow.clockwise.circle",
                            title: "デフォルトカテゴリにリセット",
                            subtitle: "基本カテゴリ（食費・交通費・娯楽・家賃）を復元する",
                            color: .blue,
                            isProcessing: isResetingCategories
                        )
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    .disabled(isResetingCategories)
                }
                
//                Section(header: Text("通知")) {
//                    Toggle("通知を有効にする", isOn: $notificationsEnabled)
//                }
                
                Section(header: Text("データ管理")) {
                    Button(action: {
                        // ハプティックフィードバックを追加
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        showingExportView = true
                    }) {
                        DataManagementButtonView(
                            icon: "square.and.arrow.up",
                            title: "CSVエクスポート",
                            color: .blue
                        )
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                }
                
                Section(header: Text("アプリ情報")) {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("1.2.0")
                            .foregroundColor(.gray)
                    }
                    // サポートページリンク
                    Button(action: {
                        // ハプティックフィードバック
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        
                        // サポートページを開く
                        if let url = URL(string: "https://shaunkotani.notion.site/249a49609c378016af1ff3f64b17a790?source=copy_link") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("サポート・お問い合わせ")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Text("ヘルプやお問い合わせはこちら")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    
                    // プライバシーポリシーリンク（オプション）
                    Button(action: {
                        // ハプティックフィードバック
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        
                        // プライバシーポリシーページを開く
                        if let url = URL(string: "https://shaunkotani.notion.site/249a49609c3780a6bd78dfd458b0d86c?source=copy_link") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised")
                                .foregroundColor(.blue)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("プライバシーポリシー")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Text("個人情報の取り扱いについて")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                    
                    // アプリレビューリンク（オプション）
                    Button(action: {
                        // ハプティックフィードバック
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        
                        // App Storeのレビューページを開く
                        // 実際のアプリIDに置き換えてください
                        if let url = URL(string: "https://itunes.apple.com/jp/app/id6749777703?action=write-review") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "star")
                                .foregroundColor(.orange)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("アプリを評価")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Text("App Storeでレビューを書く")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())

                }
                

                
                // デバッグセクション（開発時のみ表示）
                #if DEBUG
                Section(header: Text("デバッグ（開発版のみ）")) {
                    Button(action: {
                        viewModel.debugCategoryInfo()
                    }) {
                        HStack {
                            Image(systemName: "ladybug")
                                .foregroundColor(.purple)
                            Text("カテゴリ情報をコンソールに出力")
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                }
                #endif
                
                
                Section(header: Text("アプリ設定のリセット")) {
                    // 設定のリセット（改善版）
                    Button(action: {
                        // ハプティックフィードバックを追加
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        showingResetSettingsAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.orange)
                                .font(.title3)
                            Text("設定をリセット")
                                .foregroundColor(.orange)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ResponsiveButtonStyle())
                }
                
                // コピーライト表示（最下部）
                Section {
                    VStack(spacing: 8) {
                        Text("© 2025 大谷駿介")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("軽い家計簿 - Karui Kakeibo")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("設定")
//            .toolbar {
//                // キーボード用ツールバーを追加
//                ToolbarItemGroup(placement: .keyboard) {
//                    Spacer()
//                    Button("完了") {
//                        isCurrencyFocused = false
//                    }
//                    .foregroundColor(.blue)
//                    .fontWeight(.semibold)
//                }
//            }
            .sheet(isPresented: $showingExportView) {
                CSVExportView()
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $showingCategoryManagement) {
                CategoryManagementView()
                    .environmentObject(viewModel)
            }
            .alert("デフォルトカテゴリをリセット", isPresented: $showingResetCategoriesAlert) {
                Button("リセット", role: .destructive) {
                    performCategoryReset()
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("基本カテゴリ（食費・交通費・娯楽・家賃）を復元します。\n既存のデフォルトカテゴリは削除されますが、支出データは保持されます。")
            }
            .alert("設定をリセット", isPresented: $showingResetSettingsAlert) {
                Button("リセット", role: .destructive) {
                    resetSettings()
                }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("アプリの設定を初期状態に戻します。\nカテゴリや支出データは変更されません。")
            }
//            // onTapGestureを条件付きに変更
//            .simultaneousGesture(
//                TapGesture()
//                    .onEnded { _ in
//                        // キーボードが表示されている時のみキーボードを閉じる
//                        if isCurrencyFocused {
//                            isCurrencyFocused = false
//                        }
//                    }
//            )
        }
    }
    
    // MARK: - 非同期処理関数
    
    private func performCategoryReset() {
        isResetingCategories = true
        
        // 重い処理を非同期で実行
        Task {
            viewModel.resetDefaultCategories()
            
            // メインスレッドでUI更新
            await MainActor.run {
                isResetingCategories = false
                
                // 成功のハプティックフィードバック
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.success)
                
                print("⚙️ デフォルトカテゴリをリセットしました")
            }
        }
    }
    
    private func resetSettings() {
//        currency = "円"
        notificationsEnabled = true
        autoFocusAfterSave = true
        
        // その他のUserDefaultsもリセット（必要に応じて）
        UserDefaults.standard.removeObject(forKey: "doubleTapHintShown")
        
        // 成功のハプティックフィードバック
        let notificationFeedback = UINotificationFeedbackGenerator()
        notificationFeedback.notificationOccurred(.success)
        
        print("⚙️ 設定をリセットしました")
    }
}

// MARK: - カスタムボタンスタイル

struct ResponsiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .background(    // ver1.1で追加
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.2) : Color.clear)
            )
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - カスタムボタンビュー

struct CategoryManagementButtonView: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    var isProcessing: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title2)
                    .opacity(isProcessing ? 0 : 1)
                
                if isProcessing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: color))
                        .scaleEffect(0.8)
                }
            }
            .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(.primary)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            if !isProcessing {
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isProcessing ? 0.7 : 1.0)
    }
}

struct DataManagementButtonView: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            
            Text(title)
                .foregroundColor(.primary)
                .fontWeight(.medium)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - 既存のCSVExportViewとShareSheetはそのまま保持

struct CSVExportView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var exportPeriod: ExportPeriod = .all
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var isExporting = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    
    enum ExportPeriod: String, CaseIterable {
        case all = "全期間"
        case thisMonth = "今月"
        case lastMonth = "先月"
        case thisYear = "今年"
        case custom = "カスタム期間"
        
        var displayName: String {
            return self.rawValue
        }
    }
    
    var filteredExpenses: [Expense] {
        let calendar = Calendar.current
        let expenses = viewModel.expenses.sorted { $0.date < $1.date }
        
        switch exportPeriod {
        case .all:
            return expenses
        case .thisMonth:
            let now = Date()
            return expenses.filter { expense in
                calendar.isDate(expense.date, equalTo: now, toGranularity: .month)
            }
        case .lastMonth:
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            return expenses.filter { expense in
                calendar.isDate(expense.date, equalTo: lastMonth, toGranularity: .month)
            }
        case .thisYear:
            let now = Date()
            return expenses.filter { expense in
                calendar.isDate(expense.date, equalTo: now, toGranularity: .year)
            }
        case .custom:
            return expenses.filter { expense in
                expense.date >= startDate && expense.date <= endDate
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("エクスポート期間")) {
                    Picker("期間", selection: $exportPeriod) {
                        ForEach(ExportPeriod.allCases, id: \.self) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if exportPeriod == .custom {
                        DatePicker("開始日", selection: $startDate, displayedComponents: .date)
                        DatePicker("終了日", selection: $endDate, displayedComponents: .date)
                    }
                }
                
                Section(header: Text("エクスポート情報")) {
                    HStack {
                        Text("対象件数")
                        Spacer()
                        Text("\(filteredExpenses.count)件")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("期間")
                        Spacer()
                        Text(periodDescription)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text("合計金額")
                        Spacer()
                        Text("¥\(filteredExpenses.reduce(0) { $0 + $1.amount }, specifier: "%.0f")")
                            .foregroundColor(.secondary)
                            .fontWeight(.medium)
                    }
                }
                
                Section {
                    Button(action: exportToCSV) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("エクスポート中...")
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                Text("CSVファイルをエクスポート")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(10)
                    }
                    .disabled(isExporting || filteredExpenses.isEmpty)
                    .buttonStyle(ResponsiveButtonStyle())
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                
                if filteredExpenses.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text("選択した期間にデータがありません")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("CSVエクスポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                if exportedFileURL != nil {
                    Button("共有") {
                        showShareSheet = true
                    }
                    Button("OK") { }
                } else {
                    Button("OK") { }
                }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
    
    private var periodDescription: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.locale = Locale(identifier: "ja_JP")
        
        switch exportPeriod {
        case .all:
            if let first = filteredExpenses.first, let last = filteredExpenses.last {
                return "\(formatter.string(from: first.date)) - \(formatter.string(from: last.date))"
            }
            return "全期間"
        case .thisMonth:
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "yyyy年M月"
            monthFormatter.locale = Locale(identifier: "ja_JP")
            return monthFormatter.string(from: Date())
        case .lastMonth:
            let monthFormatter = DateFormatter()
            monthFormatter.dateFormat = "yyyy年M月"
            monthFormatter.locale = Locale(identifier: "ja_JP")
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            return monthFormatter.string(from: lastMonth)
        case .thisYear:
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "yyyy年"
            yearFormatter.locale = Locale(identifier: "ja_JP")
            return yearFormatter.string(from: Date())
        case .custom:
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
    }
    
    private func exportToCSV() {
        isExporting = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let csvContent = generateCSVContent()
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                let timestamp = formatter.string(from: Date())
                let fileName = "expenses_\(timestamp).csv"
                let fileURL = documentsPath.appendingPathComponent(fileName)
                
                try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
                
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.exportedFileURL = fileURL
                    self.alertTitle = "エクスポート完了"
                    self.alertMessage = "CSVファイルが正常に作成されました。\nファイル名: \(fileName)"
                    self.showAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isExporting = false
                    self.alertTitle = "エクスポートエラー"
                    self.alertMessage = "ファイルの作成に失敗しました。\nエラー: \(error.localizedDescription)"
                    self.showAlert = true
                }
            }
        }
    }
    
    private func generateCSVContent() -> String {
        var csvContent = "日付,金額,カテゴリ,メモ\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        dateFormatter.locale = Locale(identifier: "ja_JP")
        
        for expense in filteredExpenses {
            let date = dateFormatter.string(from: expense.date)
            let amount = String(format: "%.0f", expense.amount)
            let categoryName = viewModel.categories.first { $0.id == expense.categoryId }?.name ?? "不明"
            let note = expense.note.replacingOccurrences(of: "\"", with: "\"\"") // CSVエスケープ
            
            // CSVの行を作成（メモに改行やカンマが含まれる場合は引用符で囲む）
            let noteField = note.contains(",") || note.contains("\n") || note.contains("\"") ? "\"\(note)\"" : note
            csvContent += "\(date),\(amount),\(categoryName),\(noteField)\n"
        }
        
        return csvContent
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        SettingView()
            .environmentObject(ExpenseViewModel())
    }
}
