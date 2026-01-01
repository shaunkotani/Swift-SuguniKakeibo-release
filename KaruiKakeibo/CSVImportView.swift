import SwiftUI
import UniformTypeIdentifiers

/// SettingView から呼び出される CSV インポート画面
/// 期待フォーマット（エクスポートと同一）: 日付,金額,カテゴリ,メモ
/// 日付: yyyy/MM/dd
struct CSVImportView: View {
    @EnvironmentObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var isPickingFile = false
    @State private var fileName: String = ""
    @State private var rawCSVText: String = ""

    @State private var rows: [ImportRow] = []
    @State private var parseError: String?

    @State private var isImporting = false
    @State private var showResultAlert = false
    @State private var resultTitle = ""
    @State private var resultMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("ファイル選択")) {
                    Button { isPickingFile = true } label: {
                        HStack {
                            Image(systemName: "doc")
                            Text("CSVファイルを選択")
                            Spacer()
                            if !fileName.isEmpty { Text(fileName).foregroundColor(.secondary) }
                        }
                    }
                }

                if let parseError {
                    Section(header: Text("エラー")) {
                        Text(parseError)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }

                if !rows.isEmpty {
                    Section(header: Text("プレビュー")) {
                        summaryRow

                        ForEach(rows.prefix(20)) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(r.dateText)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("¥\(r.amountText)")
                                }

                                Text("カテゴリ: \(r.categoryResolvedName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if !r.note.isEmpty {
                                    Text("メモ: \(r.note)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }

                                if let err = r.error {
                                    Text("⚠️ \(err)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        if rows.count > 20 {
                            Text("…ほか \(rows.count - 20) 件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("CSVインポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                if !rows.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            importToDB()
                        } label: {
                            HStack {
                                if isImporting { ProgressView().scaleEffect(0.9) }
                                Text(isImporting ? "インポート中..." : "インポート")
                            }
                        }
                        .disabled(isImporting || rows.allSatisfy { $0.error != nil })
                    }
                }
            }
            .fileImporter(
                isPresented: $isPickingFile,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText, UTType.text],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
            .alert(resultTitle, isPresented: $showResultAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text(resultMessage)
            }
        }
    }

    private var summaryRow: some View {
        let valid = rows.filter { $0.error == nil }.count
        let invalid = rows.filter { $0.error != nil }.count

        return VStack(alignment: .leading, spacing: 6) {
            Text("読み込み件数: \(rows.count)件")
            Text("インポート可能: \(valid)件 / エラー: \(invalid)件")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - File handling

    private func handleFilePick(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            fileName = url.lastPathComponent

            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
                parseError = "ファイルを文字列として読み込めませんでした（UTF-8/Shift_JIS）。"
                rows = []
                return
            }

            rawCSVText = text
            parseError = nil
            rows = []

            // ★重要：カテゴリ解決は viewModel の非同期更新に依存しない（DB直参照で同期処理）
            Task { @MainActor in
                prepareCategoriesAndBuildPreview(csvText: rawCSVText)
            }
        } catch {
            parseError = "ファイル選択に失敗しました: \(error.localizedDescription)"
            rows = []
        }
    }

    // MARK: - Parse & Preview

    @MainActor
    private func prepareCategoriesAndBuildPreview(csvText: String) {
        let table = CSVParser.parse(csvText)
        guard !table.isEmpty else {
            parseError = "CSVが空です。"
            rows = []
            return
        }

        // ヘッダ検証（エクスポート形式と同一）
        let header = table[0].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let expected = ["日付", "金額", "カテゴリ", "メモ"]
        guard header == expected else {
            parseError = "ヘッダが一致しません。\n期待: \(expected.joined(separator: ","))\n実際: \(header.joined(separator: ","))"
            rows = []
            return
        }

        // 1) 「不明」を保証
        ExpenseDatabaseManager.shared.ensureUnknownCategoryExists()

        // 2) CSV内カテゴリ名を収集（空は除外）
        let csvCategoryNames: Set<String> = Set(
            table.dropFirst().compactMap { row in
                guard row.count >= 3 else { return nil }
                let name = row[2].trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : name
            }
        )

        // 3) DBから同期的に既存カテゴリを取得 → 未知カテゴリを自動作成
        let existing = ExpenseDatabaseManager.shared.fetchFullCategories()
        let existingNames = Set(existing.map { $0.name })
        let toCreate = csvCategoryNames.subtracting(existingNames)
        if !toCreate.isEmpty {
            ExpenseDatabaseManager.shared.createCategoriesIfNeeded(
                names: Array(toCreate).sorted(),
                defaultIcon: "tag.fill",
                defaultColor: "gray"
            )
        }

        // 4) 必ず最新カテゴリを再取得して、categoryId解決に使う
        let latestCategories = ExpenseDatabaseManager.shared.fetchFullCategories()

        parseError = nil
        rows = buildPreviewRows(from: table, categories: latestCategories)
    }

    private func buildPreviewRows(from table: [[String]], categories: [FullCategory]) -> [ImportRow] {
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0.id) })
        let unknownId = categoryMap["不明"] ?? 0

        let df = DateFormatter()
        df.dateFormat = "yyyy/MM/dd"
        df.locale = Locale(identifier: "ja_JP")

        let userId = 1

        var built: [ImportRow] = []
        for (i, row) in table.dropFirst().enumerated() {
            let line = i + 2

            if row.count < 4 {
                built.append(.error(line: line, message: "列数が不足しています（4列必要）"))
                continue
            }

            let dateStr = row[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let amountStr = row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let catStr = row[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let noteStr = row[3]

            guard let date = df.date(from: dateStr) else {
                built.append(.error(line: line, message: "日付の形式が不正です: \(dateStr)"))
                continue
            }

            let normalizedAmount = amountStr.replacingOccurrences(of: ",", with: "")
            guard let amount = Double(normalizedAmount) else {
                built.append(.error(line: line, message: "金額の形式が不正です: \(amountStr)"))
                continue
            }

            let categoryId = (catStr.isEmpty ? unknownId : (categoryMap[catStr] ?? unknownId))
            let resolvedName = categories.first { $0.id == categoryId }?.name ?? "不明"

            let exp = Expense(
                id: 0,
                amount: amount,
                date: date,
                note: noteStr,
                categoryId: categoryId,
                userId: userId
            )

            built.append(
                ImportRow(
                    id: UUID(),
                    line: line,
                    dateText: dateStr,
                    amountText: amountStr,
                    categoryRawName: catStr,
                    categoryResolvedName: resolvedName,
                    note: noteStr,
                    expense: exp,
                    error: nil
                )
            )
        }

        return built
    }

    // MARK: - Import

    private func importToDB() {
        isImporting = true

        Task {
            let validExpenses = rows.compactMap { $0.error == nil ? $0.expense : nil }
            ExpenseDatabaseManager.shared.insertExpenses(expenses: validExpenses)

            await MainActor.run {
                // ★カテゴリ/支出を両方同期（カレンダー/集計のズレを防ぐ）
                viewModel.refreshAllData()
                isImporting = false
                resultTitle = "インポート完了"
                resultMessage = "追加: \(validExpenses.count)件\n（エラー行はインポートされません）"
                showResultAlert = true
            }
        }
    }
}

// MARK: - Models

struct ImportRow: Identifiable {
    let id: UUID
    let line: Int
    let dateText: String
    let amountText: String
    let categoryRawName: String
    let categoryResolvedName: String
    let note: String
    let expense: Expense?
    let error: String?

    static func error(line: Int, message: String) -> ImportRow {
        ImportRow(
            id: UUID(),
            line: line,
            dateText: "",
            amountText: "",
            categoryRawName: "",
            categoryResolvedName: "",
            note: "",
            expense: nil,
            error: message
        )
    }
}

// MARK: - CSV Parser (quoted/newlines対応)

enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""

        var inQuotes = false
        var i = text.startIndex

        func endField() {
            row.append(field)
            field = ""
        }

        func endRow() {
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                rows.append(row)
            }
            row = []
        }

        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        field.append("\"") // "" -> "
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    endField()
                } else if c == "\n" {
                    endField()
                    endRow()
                } else if c == "\r" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\n" {
                        // skip
                    } else {
                        endField()
                        endRow()
                    }
                } else {
                    field.append(c)
                }
            }

            i = text.index(after: i)
        }

        endField()
        if !row.isEmpty { endRow() }
        return rows
    }
}

