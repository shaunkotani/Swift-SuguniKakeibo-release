//
//  SavingsView.swift
//  かるい家計簿！
//
//  Created by 大谷駿介 on 2026/01/12.
//

import SwiftUI

/// 「貯金チェック（今月）」を独立Viewとして切り出したもの
/// - 単体タブとしても、他のForm内のパーツとしても使えるようにしています。
struct SavingsView: View {
    @ObservedObject var store: MemoStoreModel
    @StateObject private var history = SavingsHistoryStore()

    var body: some View {
        NavigationStack {
            Form {
                SavingsCheckSection(store: store, history: history)
            }
            .navigationTitle("貯金")
        }
    }
}

// MARK: - Savings History (local persistence)

struct SavingsEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var amount: Int
    var memo: String
    /// Toggle（"今月、貯金できた"）で自動追加された差分エントリ
    var isAutoFromCheck: Bool = false
}

final class SavingsHistoryStore: ObservableObject {
    @Published private(set) var entries: [SavingsEntry] = []

    private let key = "savings_entries_v1"

    init() {
        load()
    }

    func add(amount: Int, date: Date = Date(), memo: String = "", isAutoFromCheck: Bool = false) {
        guard amount != 0 else { return }
        let new = SavingsEntry(date: date, amount: amount, memo: memo, isAutoFromCheck: isAutoFromCheck)
        entries.insert(new, at: 0)
        save()
    }

    func update(_ entry: SavingsEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
        entries.sort(by: { $0.date > $1.date })
        save()
    }

    func delete(at offsets: IndexSet, within list: [SavingsEntry]) {
        let ids = offsets.map { list[$0].id }
        entries.removeAll(where: { ids.contains($0.id) })
        save()
    }

    func removeAutoEntries(inMonthOf date: Date) {
        let cal = Calendar.current
        entries.removeAll(where: {
            $0.isAutoFromCheck && cal.isDate($0.date, equalTo: date, toGranularity: .month)
        })
        save()
    }

    func sum(inMonthOf date: Date) -> Int {
        let cal = Calendar.current
        return entries
            .filter { cal.isDate($0.date, equalTo: date, toGranularity: .month) }
            .map { $0.amount }
            .reduce(0, +)
    }

    func entries(inMonthOf date: Date) -> [SavingsEntry] {
        let cal = Calendar.current
        return entries
            .filter { cal.isDate($0.date, equalTo: date, toGranularity: .month) }
            .sorted(by: { $0.date > $1.date })
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            entries = []
            return
        }
        do {
            entries = try JSONDecoder().decode([SavingsEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            // 保存失敗時は握りつぶし（UIは動かす）
        }
    }
}

// MARK: - UI Parts

struct SavingsProgressBar: View {
    let title: String
    let current: Int
    let target: Int

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(current) / Double(target), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(current) / \(max(target, 0)) 円")
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 10)

                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * progress, height: 10)
                        .animation(.easeInOut(duration: 0.35), value: progress)
                }
            }
            .frame(height: 10)

            if target > 0 {
                let remaining = max(target - current, 0)
                Text(remaining == 0 ? "達成！" : "残り \(remaining) 円")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Text("金額を入力すると進捗が表示されます")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct AddOrEditSavingsEntrySheet: View {
    enum Mode {
        case add
        case edit
    }

    let mode: Mode
    @State private var amountText: String
    @State private var date: Date
    @State private var memo: String

    let onSave: (Int, Date, String) -> Void
    let onCancel: () -> Void

    init(
        mode: Mode,
        initialAmount: Int = 0,
        initialDate: Date = Date(),
        initialMemo: String = "",
        onSave: @escaping (Int, Date, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        _amountText = State(initialValue: initialAmount == 0 ? "" : String(initialAmount))
        _date = State(initialValue: initialDate)
        _memo = State(initialValue: initialMemo)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("金額（円）", text: $amountText)
                        .keyboardType(.numberPad)

                    DatePicker("日付", selection: $date, displayedComponents: [.date])

                    TextField("メモ（任意）", text: $memo)
                }
            }
            .navigationTitle(mode == .add ? "貯金を追加" : "貯金を編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let amount = Int(amountText.filter({ $0.isNumber })) ?? 0
                        onSave(amount, date, memo)
                    }
                    .disabled((Int(amountText.filter({ $0.isNumber })) ?? 0) <= 0)
                }
            }
        }
    }
}

// MARK: - Main Section

/// Form内で再利用できる「貯金チェック（今月）」セクション
struct SavingsCheckSection: View {
    @ObservedObject var store: MemoStoreModel
    @ObservedObject var history: SavingsHistoryStore

    @State private var showAddSheet = false
    @State private var editingEntry: SavingsEntry? = nil
    @State private var isApplyingCheckSideEffect = false

    // 今月いくら貯金するか（予定額）
    @State private var plannedThisMonthAmount: Int = 0

    private var now: Date { Date() }
    private var monthEntries: [SavingsEntry] { history.entries(inMonthOf: now) }
    private var monthSaved: Int { history.sum(inMonthOf: now) }
    private var monthSavedManual: Int {
        monthEntries
            .filter { !$0.isAutoFromCheck }
            .map { $0.amount }
            .reduce(0, +)
    }
    private var totalSaved: Int {
        history.entries.map { $0.amount }.reduce(0, +)
    }

    private var plannedKeyForThisMonth: String {
        let df = DateFormatter()
        df.calendar = Calendar.current
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "yyyyMM"
        return "savings_plan_\(df.string(from: now))"
    }

    private func loadPlannedThisMonth() {
        plannedThisMonthAmount = UserDefaults.standard.integer(forKey: plannedKeyForThisMonth)
    }

    private func savePlannedThisMonth() {
        UserDefaults.standard.set(plannedThisMonthAmount, forKey: plannedKeyForThisMonth)
    }

    private func syncCheckWithMonthProgress() {
        guard !isApplyingCheckSideEffect else { return }
        let plan = max(plannedThisMonthAmount, 0)
        guard plan > 0 else { return }
        let done = monthSaved >= plan
        if store.savingsCheckedThisMonth != done {
            store.savingsCheckedThisMonth = done
        }
    }

    private func applyAutoFillIfChecked() {
        guard store.savingsCheckedThisMonth else { return }
        let plan = max(plannedThisMonthAmount, 0)
        let diff = max(plan - monthSavedManual, 0)
        if diff > 0 {
            history.add(amount: diff, date: now, memo: "チェックで貯金", isAutoFromCheck: true)
        }
    }

    private var isEditSheetPresented: Binding<Bool> {
        Binding(
            get: { editingEntry != nil },
            set: { newValue in
                if !newValue {
                    editingEntry = nil
                }
            }
        )
    }

    @ViewBuilder
    private var checkSection: some View {
        Section(
            header: Text("貯金チェック（今月）"),
            footer: Text("翌月になるとチェックが外れます")
                .foregroundColor(.secondary)
        ) {
            HStack {
                Text("総目標")
                Spacer()
                TextField("300000", value: $store.savingsTargetAmount, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text("円")
                    .foregroundColor(.secondary)
            }

            SavingsProgressBar(title: "累計貯金（目標まで）", current: totalSaved, target: Int(store.savingsTargetAmount))

            // ▼要望：チェックの上あたりに「今月いくら貯金するか」入力欄
            HStack {
                Text("今月の予定")
                Spacer()
                TextField("20000", value: $plannedThisMonthAmount, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                Text("円")
                    .foregroundColor(.secondary)
            }

            SavingsProgressBar(title: "今月の貯金（進捗）", current: monthSaved, target: plannedThisMonthAmount)

            Toggle(isOn: $store.savingsCheckedThisMonth) {
                Text("今月、貯金できた")
            }

            Button {
                showAddSheet = true
            } label: {
                Label("貯金を追加", systemImage: "plus.circle.fill")
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section(
            header: Text("貯金履歴（今月）"),
            footer: Text("チェックをONにすると、今月の予定額に達するまで不足分が自動で追加されます")
                .foregroundColor(.secondary)
        ) {
            if monthEntries.isEmpty {
                Text("まだ貯金履歴がありません")
                    .foregroundColor(.secondary)
            } else {
                ForEach(monthEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date, style: .date)
                            if !entry.memo.isEmpty {
                                Text(entry.memo)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(entry.amount) 円")
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !entry.isAutoFromCheck {
                            editingEntry = entry
                        }
                    }
                }
                .onDelete { offsets in
                    history.delete(at: offsets, within: monthEntries)
                }
            }
        }
    }

    var body: some View {
        Group {
            checkSection
            historySection
        }
        .sheet(isPresented: $showAddSheet) {
            AddOrEditSavingsEntrySheet(mode: .add, onSave: { amount, date, memo in
                history.add(amount: amount, date: date, memo: memo)
                showAddSheet = false
            }, onCancel: {
                showAddSheet = false
            })
        }
        .sheet(isPresented: isEditSheetPresented) {
            // item-based sheetは型推論が重くなりがちなので Bool sheet + if-let にする
            if let entry = editingEntry {
                AddOrEditSavingsEntrySheet(
                    mode: .edit,
                    initialAmount: entry.amount,
                    initialDate: entry.date,
                    initialMemo: entry.memo,
                    onSave: { amount, date, memo in
                        var updated = entry
                        updated.amount = amount
                        updated.date = date
                        updated.memo = memo
                        history.update(updated)
                        editingEntry = nil
                    },
                    onCancel: {
                        editingEntry = nil
                    }
                )
            } else {
                EmptyView()
            }
        }
        .onAppear {
            loadPlannedThisMonth()
            syncCheckWithMonthProgress()
        }
        .onChange(of: plannedThisMonthAmount) { _, _ in
            savePlannedThisMonth()
            applyAutoFillIfChecked()
            syncCheckWithMonthProgress()
        }
        .onChange(of: store.savingsCheckedThisMonth) { _, newValue in
            guard !isApplyingCheckSideEffect else { return }
            isApplyingCheckSideEffect = true
            defer { isApplyingCheckSideEffect = false }

            if newValue {
                applyAutoFillIfChecked()
            } else {
                history.removeAutoEntries(inMonthOf: now)
            }
        }
        .onChange(of: history.entries) { _, _ in
            syncCheckWithMonthProgress()
        }
    }
}

#Preview {
    SavingsView(store: MemoStoreModel())
}

