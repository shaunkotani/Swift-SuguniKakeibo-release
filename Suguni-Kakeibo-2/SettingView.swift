//
//  SettingView.swift (デフォルトカテゴリリセット機能追加版)
//  Suguni-Kakeibo-2
//
//  Created by 大谷駿介 on 2025/07/29.
//

import SwiftUI

struct SettingView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @AppStorage("currency") private var currency = "円"
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("autoFocusAfterSave") private var autoFocusAfterSave = true
    @State private var showingExportView = false
    @State private var showingCategoryManagement = false
    @State private var showingResetCategoriesAlert = false
    @State private var showingResetSettingsAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("入力設定")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("保存後に自動で金額入力にフォーカス", isOn: $autoFocusAfterSave)
                        
                        Text("支出保存後、次の入力のために金額フィールドに自動でカーソルを移動します")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("通貨設定")) {
                    TextField("通貨単位", text: $currency)
                }
                
                // カテゴリ管理セクション
                Section(header: Text("カテゴリ管理")) {
                    Button(action: {
                        showingCategoryManagement = true
                    }) {
                        HStack {
                            Image(systemName: "tag.circle")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("カテゴリの編集")
                                    .foregroundColor(.primary)
                                Text("カテゴリの追加・編集・表示設定")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // デフォルトカテゴリリセット機能を追加
                    Button(action: {
                        showingResetCategoriesAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise.circle")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("デフォルトカテゴリをリセット")
                                    .foregroundColor(.primary)
                                Text("基本カテゴリ（食費・交通費・娯楽・家賃）を復元")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Section(header: Text("通知")) {
                    Toggle("通知を有効にする", isOn: $notificationsEnabled)
                }
                
                Section(header: Text("データ管理")) {
                    Button(action: {
                        showingExportView = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                            Text("CSVエクスポート")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Section(header: Text("アプリ情報")) {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.gray)
                    }
                    
                    // 設定のリセット
                    Button(action: {
                        showingResetSettingsAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.orange)
                            Text("設定をリセット")
                                .foregroundColor(.orange)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
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
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                #endif
            }
            .navigationTitle("設定")
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
                    viewModel.resetDefaultCategories()
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
        }
    }
    
    private func resetSettings() {
        currency = "円"
        notificationsEnabled = true
        autoFocusAfterSave = true
        
        // その他のUserDefaultsもリセット（必要に応じて）
        UserDefaults.standard.removeObject(forKey: "doubleTapHintShown")
        
        print("⚙️ 設定をリセットしました")
    }
}

// 既存のCSVExportViewとShareSheetはそのまま保持
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
                    .buttonStyle(PlainButtonStyle())
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
