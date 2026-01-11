import SwiftUI
import Foundation
import Combine

// MARK: - Models
struct MemoTodoList: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
}

struct MemoTodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
    var listId: UUID
    var createdAt: Date = Date()
    var doneAt: Date? = nil
}

// MARK: - Store
final class MemoStoreModel: ObservableObject {
    // Keys
    private let memoKey = "memo.freeText.v1"
    private let todoListsKey = "memo.todoLists.v1"
    private let todosKeyV2 = "memo.todos.v2" // listId対応

    // 旧カテゴリ制の移行用（以前の実装で使っていたキー）
    private let legacyTodosKey = "memo.todos.v1"

    private let savingsTargetKey = "memo.savingsTargetAmount.v1"
    private let savingsCheckedKey = "memo.savingsChecked.v1"
    private let savingsCheckedMonthKey = "memo.savingsCheckedMonth.v1"

    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    @Published var freeMemo: String = ""
    @Published var todoLists: [MemoTodoList] = []
    @Published var todos: [MemoTodoItem] = []

    @Published var savingsTargetAmount: Double = 0
    @Published var savingsCheckedThisMonth: Bool = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        ensureAtLeastOneList()
        rolloverSavingsIfNeeded()
        setupAutosave()
    }

    // MARK: Lists
    @discardableResult
    func addList(name: String) -> MemoTodoList? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if todoLists.contains(where: { $0.name == trimmed }) { return nil }
        let list = MemoTodoList(name: trimmed)
        todoLists.append(list)
        return list
    }

    func renameList(_ id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let idx = todoLists.firstIndex(where: { $0.id == id }) else { return }
        if todoLists.contains(where: { $0.id != id && $0.name == trimmed }) { return }
        todoLists[idx].name = trimmed
    }

    func deleteList(_ id: UUID) {
        todoLists.removeAll { $0.id == id }
        todos.removeAll { $0.listId == id }
        ensureAtLeastOneList()
    }

    func listName(for id: UUID?) -> String {
        guard let id else { return "ToDo" }
        return todoLists.first(where: { $0.id == id })?.name ?? "ToDo"
    }

    func defaultListId() -> UUID {
        ensureAtLeastOneList()
        return todoLists.first!.id
    }

    private func ensureAtLeastOneList() {
        if todoLists.isEmpty {
            todoLists = [MemoTodoList(name: "ToDo")]
        }
    }

    // MARK: Todos
    func addTodo(title: String, listId: UUID) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.insert(MemoTodoItem(title: trimmed, listId: listId), at: 0)
    }

    func toggleTodo(_ id: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[idx].isDone.toggle()
        todos[idx].doneAt = todos[idx].isDone ? Date() : nil
    }

    func deleteTodo(_ id: UUID) {
        todos.removeAll { $0.id == id }
    }

    func updateTodoTitle(_ id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[idx].title = trimmed
    }

    func todos(in listId: UUID) -> [MemoTodoItem] {
        todos.filter { $0.listId == listId }
    }

    // MARK: Monthly savings rollover
    private func currentYearMonthString() -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.calendar = Calendar(identifier: .gregorian)
        df.dateFormat = "yyyy-MM"
        return df.string(from: Date())
    }

    private func rolloverSavingsIfNeeded() {
        let current = currentYearMonthString()
        let saved = defaults.string(forKey: savingsCheckedMonthKey)
        if saved != current {
            savingsCheckedThisMonth = false
            defaults.set(current, forKey: savingsCheckedMonthKey)
        }
    }

    // MARK: Load / Save
    private func load() {
        freeMemo = defaults.string(forKey: memoKey) ?? ""

        if let data = defaults.data(forKey: todoListsKey) {
            do { todoLists = try JSONDecoder().decode([MemoTodoList].self, from: data) }
            catch { todoLists = [] }
        } else {
            todoLists = []
        }

        if let data = defaults.data(forKey: todosKeyV2) {
            do { todos = try JSONDecoder().decode([MemoTodoItem].self, from: data) }
            catch { todos = [] }
        } else {
            todos = []
            migrateLegacyTodosIfNeeded()
        }

        savingsTargetAmount = defaults.double(forKey: savingsTargetKey)
        savingsCheckedThisMonth = defaults.bool(forKey: savingsCheckedKey)
    }

    // 旧：kindベースのTodoItem（移行用）
    private struct LegacyTodoItem: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var title: String
        var isDone: Bool = false
        var kind: String
        var createdAt: Date = Date()
        var doneAt: Date? = nil
    }

    private func migrateLegacyTodosIfNeeded() {
        guard let data = defaults.data(forKey: legacyTodosKey) else { return }
        do {
            let legacy = try JSONDecoder().decode([LegacyTodoItem].self, from: data)
            guard !legacy.isEmpty else { return }

            var map: [String: UUID] = [:]
            for item in legacy {
                if map[item.kind] == nil {
                    let listName: String
                    switch item.kind {
                    case "shopping": listName = "買い物リスト"
                    case "savings":  listName = "貯金ToDo"
                    case "general":  listName = "その他ToDo"
                    default:          listName = item.kind
                    }
                    let list = MemoTodoList(name: listName)
                    todoLists.append(list)
                    map[item.kind] = list.id
                }
            }

            let converted: [MemoTodoItem] = legacy.compactMap { l in
                guard let listId = map[l.kind] else { return nil }
                return MemoTodoItem(id: l.id, title: l.title, isDone: l.isDone, listId: listId, createdAt: l.createdAt, doneAt: l.doneAt)
            }
            todos = converted

            do {
                let v2 = try JSONEncoder().encode(todos)
                defaults.set(v2, forKey: todosKeyV2)
            } catch {
                // no-op
            }
        } catch {
            // no-op
        }
    }

    private func setupAutosave() {
        $freeMemo
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                self.defaults.set(text, forKey: self.memoKey)
            }
            .store(in: &cancellables)

        $todoLists
            .dropFirst()
            .sink { [weak self] lists in
                guard let self else { return }
                do {
                    let data = try JSONEncoder().encode(lists)
                    self.defaults.set(data, forKey: self.todoListsKey)
                } catch {
                    // no-op
                }
            }
            .store(in: &cancellables)

        $todos
            .dropFirst()
            .sink { [weak self] items in
                guard let self else { return }
                do {
                    let data = try JSONEncoder().encode(items)
                    self.defaults.set(data, forKey: self.todosKeyV2)
                } catch {
                    // no-op
                }
            }
            .store(in: &cancellables)

        $savingsTargetAmount
            .dropFirst()
            .sink { [weak self] v in
                guard let self else { return }
                self.defaults.set(v, forKey: self.savingsTargetKey)
            }
            .store(in: &cancellables)

        $savingsCheckedThisMonth
            .dropFirst()
            .sink { [weak self] v in
                guard let self else { return }
                self.defaults.set(v, forKey: self.savingsCheckedKey)
            }
            .store(in: &cancellables)
    }
}

// MARK: - View
struct MemoView: View {
    @StateObject private var store = MemoStoreModel()

    // ToDoリスト選択
    @State private var selectedListId: UUID? = nil

    // ToDo検索 / 表示制御
    @State private var todoSearchText: String = ""
    @State private var hideCompleted: Bool = false

    // 追加ToDo（フローティングボタン → アラート入力）
    @State private var showAddTodoAlert: Bool = false
    @State private var addTodoTitle: String = ""

    // リスト名のクイック編集（タブ長押しメニュー）
    @State private var quickEditingListId: UUID? = nil
    @State private var quickEditingListName: String = ""
    @State private var showQuickEditListAlert: Bool = false

    // リスト削除（タブ長押しメニュー）
    @State private var quickDeleteListId: UUID? = nil
    @State private var showQuickDeleteListDialog: Bool = false

    // リスト管理シート
    @State private var showManageListsSheet: Bool = false

    // ToDoインライン編集
    @State private var editingTodoId: UUID? = nil
    @State private var editingTodoTitle: String = ""

    // キーボード制御（タップ or スクロールで閉じる）
    @FocusState private var focusedField: Field?
    @FocusState private var focusedTodoId: UUID?

    private enum Field: Hashable {
        case memo
        case savingsAmount
    }

    private func commitEditingIfNeeded() {
        guard let id = editingTodoId else { return }
        let trimmed = editingTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            // 空で確定されたら、その項目を削除
            store.deleteTodo(id)
        } else {
            store.updateTodoTitle(id, title: trimmed)
        }

        editingTodoId = nil
        editingTodoTitle = ""
    }

    private func dismissKeyboard() {
        commitEditingIfNeeded()
        focusedField = nil
        focusedTodoId = nil
        // InputViewと同じ方式（UIKit側で確実に閉じる）
        UIApplication.shared.closeKeyboard()
    }

    private var effectiveListId: UUID {
        if let selectedListId, store.todoLists.contains(where: { $0.id == selectedListId }) {
            return selectedListId
        }
        return store.defaultListId()
    }

    private var effectiveListName: String {
        store.listName(for: effectiveListId)
    }


    private var baseItemsForSelectedList: [MemoTodoItem] {
        store.todos(in: effectiveListId)
    }

    private var filteredItemsForSelectedList: [MemoTodoItem] {
        let q = todoSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return baseItemsForSelectedList }
        return baseItemsForSelectedList.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }

    private var activeItems: [MemoTodoItem] {
        filteredItemsForSelectedList
            .filter { !$0.isDone }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var doneItems: [MemoTodoItem] {
        filteredItemsForSelectedList
            .filter { $0.isDone }
            .sorted { ($0.doneAt ?? $0.createdAt) > ($1.doneAt ?? $1.createdAt) }
    }

    private var todoSummaryText: String {
        let total = baseItemsForSelectedList.count
        let done = baseItemsForSelectedList.filter { $0.isDone }.count
        if total == 0 {
            return "ToDoなし"
        }
        return "\(done)/\(total) 完了"
    }

    var body: some View {
        Form {
            // 自由メモ
            Section(header: Text("自由メモ")) {
                ZStack(alignment: .topLeading) {
                    if store.freeMemo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("例）今月の目標、固定費の見直し、やることメモ…")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $store.freeMemo)
                        .frame(minHeight: 160)
                        .focused($focusedField, equals: .memo)
                }
            }

            // ToDo（タブ + 一覧を1つのカードにまとめる）
            Section {
                // タブ＋サマリー（この行だけセパレータ無し）
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.todoLists) { list in
                                MemoTodoListTab(
                                    name: list.name,
                                    isSelected: list.id == effectiveListId,
                                    onSelect: {
                                        selectedListId = list.id
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        dismissKeyboard()
                                    },
                                    onRename: {
                                        quickEditingListId = list.id
                                        quickEditingListName = list.name
                                        showQuickEditListAlert = true
                                    },
                                    onDelete: {
                                        quickDeleteListId = list.id
                                        showQuickDeleteListDialog = true
                                    }
                                )
                            }

                            Button {
                                showManageListsSheet = true
                                dismissKeyboard()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.subheadline.weight(.bold))
                                    .frame(width: 28, height: 28)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("ToDoリストを追加")
                        }
                        .padding(.vertical, 4)
                    }

                    HStack {
                        Text(todoSummaryText)
                            .foregroundColor(.secondary)
                            .font(.footnote)
                        Spacer()
                        Toggle("完了を隠す", isOn: $hideCompleted)
                            .labelsHidden()
                    }

                    Divider().opacity(0.35)
                }
                .padding(.vertical, 4)
                .listRowSeparator(.hidden)

                // リスト名（カード内の小見出し）
                HStack {
                    Text(effectiveListName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .listRowSeparator(.hidden)

                // ToDo項目（各行にスワイプを効かせる）
                if activeItems.isEmpty && (hideCompleted || doneItems.isEmpty) {
                    if todoSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("右下の＋から追加")
                            .foregroundColor(.secondary)
                    } else {
                        Text("一致するToDoがありません")
                            .foregroundColor(.secondary)
                    }
                } else {
                    ForEach(activeItems) { item in
                        MemoTodoRow(
                            item: item,
                            isEditing: editingTodoId == item.id,
                            editingText: $editingTodoTitle,
                            focusedTodoId: $focusedTodoId,
                            onCommitEdit: {
                                commitEditingIfNeeded()
                            },
                            onToggle: { store.toggleTodo(item.id) },
                            onEdit: {
                                editingTodoId = item.id
                                editingTodoTitle = item.title
                                focusedTodoId = item.id
                            },
                            onDelete: { store.deleteTodo(item.id) }
                        )
                    }

                    if !hideCompleted {
                        ForEach(doneItems) { item in
                            MemoTodoRow(
                                item: item,
                                isEditing: editingTodoId == item.id,
                                editingText: $editingTodoTitle,
                                focusedTodoId: $focusedTodoId,
                                onCommitEdit: {
                                    commitEditingIfNeeded()
                                },
                                onToggle: { store.toggleTodo(item.id) },
                                onEdit: {
                                    editingTodoId = item.id
                                    editingTodoTitle = item.title
                                    focusedTodoId = item.id
                                },
                                onDelete: { store.deleteTodo(item.id) }
                            )
                        }
                    }
                }

                // カード内の右下に「追加」ボタン
                HStack {
                    Spacer()
                    Button {
                        addTodoTitle = ""
                        showAddTodoAlert = true
                        dismissKeyboard()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 44))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("ToDoを追加")
                }
                .padding(.top, 2)
                .listRowSeparator(.hidden)
            } header: {
                HStack {
                    Text("ToDo")
                    Spacer()
                    Button {
                        showManageListsSheet = true
                        dismissKeyboard()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("ToDoリストを管理")
                }
            }


            // 毎月の貯金チェック（ToDoとは独立）
            Section(header: Text("貯金チェック（今月）")) {
                HStack {
                    Text("目標")
                    Spacer()
                    TextField("30000", value: $store.savingsTargetAmount, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .savingsAmount)
                    Text("円")
                        .foregroundColor(.secondary)
                }

                Toggle(isOn: $store.savingsCheckedThisMonth) {
                    Text("今月、貯金できた")
                }
            }
        }
        .onAppear {
            if selectedListId == nil {
                selectedListId = store.defaultListId()
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                dismissKeyboard()
            }
        )
        // .animation(.default, value: store.todos)
        .navigationTitle("メモ")
        .searchable(text: $todoSearchText, prompt: "ToDoを検索")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showManageListsSheet = true
                    dismissKeyboard()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .accessibilityLabel("ToDoリストを管理")
            }
        }
        .sheet(isPresented: $showManageListsSheet) {
            ManageTodoListsView(store: store, selectedListId: $selectedListId)
        }
        .alert("ToDoを追加", isPresented: $showAddTodoAlert) {
            TextField("内容", text: $addTodoTitle)
            Button("追加") {
                let trimmed = addTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    store.addTodo(title: trimmed, listId: effectiveListId)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                addTodoTitle = ""
            }
            Button("キャンセル", role: .cancel) {
                addTodoTitle = ""
            }
        }
        .alert("リスト名を変更", isPresented: $showQuickEditListAlert) {
            TextField("リスト名", text: $quickEditingListName)
            Button("保存") {
                if let id = quickEditingListId {
                    store.renameList(id, to: quickEditingListName)
                    selectedListId = id
                }
                quickEditingListId = nil
                quickEditingListName = ""
            }
            Button("キャンセル", role: .cancel) {
                quickEditingListId = nil
                quickEditingListName = ""
            }
        }
        .confirmationDialog(
            "リストを削除しますか？（中のToDoも削除されます）",
            isPresented: $showQuickDeleteListDialog,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let id = quickDeleteListId {
                    let deletingSelected = (id == effectiveListId)
                    store.deleteList(id)
                    if deletingSelected {
                        selectedListId = store.defaultListId()
                    }
                }
                quickDeleteListId = nil
            }
            Button("キャンセル", role: .cancel) {
                quickDeleteListId = nil
            }
        }
    }
}

private struct MemoTodoRow: View {
    let item: MemoTodoItem
    let isEditing: Bool
    @Binding var editingText: String
    let focusedTodoId: FocusState<UUID?>.Binding
    let onCommitEdit: () -> Void
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggle()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            if isEditing {
                TextField("", text: $editingText)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .focused(focusedTodoId, equals: item.id)
                    .onSubmit {
                        onCommitEdit()
                    }
            } else {
                Button {
                    onEdit()
                } label: {
                    HStack(spacing: 0) {
                        Text(item.title)
                            .strikethrough(item.isDone)
                            .foregroundColor(item.isDone ? .secondary : .primary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isEditing {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("削除", systemImage: "trash")
                }

                Button {
                    onEdit()
                } label: {
                    Label("編集", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
    }
}

private struct ManageTodoListsView: View {
    @ObservedObject var store: MemoStoreModel
    @Binding var selectedListId: UUID?

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedNewListField: Bool

    @State private var newListName: String = ""

    @State private var editingListId: UUID? = nil
    @State private var editingListName: String = ""
    @State private var showEditListAlert: Bool = false

    @State private var deleteListCandidate: MemoTodoList? = nil
    @State private var showDeleteListDialog: Bool = false

    private var effectiveSelectedId: UUID {
        if let selectedListId, store.todoLists.contains(where: { $0.id == selectedListId }) {
            return selectedListId
        }
        return store.defaultListId()
    }

    private func addList() {
        if let created = store.addList(name: newListName) {
            selectedListId = created.id
            newListName = ""
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        focusedNewListField = false
        UIApplication.shared.closeKeyboard()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        TextField("新しいリスト名", text: $newListName)
                            .textInputAutocapitalization(.never)
                            .submitLabel(.done)
                            .focused($focusedNewListField)
                            .onSubmit { addList() }

                        Button {
                            addList()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } footer: {
                    Text("リストをタップすると選択されます。スワイプで名前変更／削除できます。")
                }

                Section {
                    ForEach(store.todoLists) { list in
                        let total = store.todos(in: list.id).count
                        let done = store.todos(in: list.id).filter { $0.isDone }.count

                        HStack(spacing: 12) {
                            Text(list.name)
                            Spacer()
                            if total > 0 {
                                Text("\(done)/\(total)")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                            }
                            if list.id == effectiveSelectedId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedListId = list.id
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteListCandidate = list
                                showDeleteListDialog = true
                            } label: {
                                Label("削除", systemImage: "trash")
                            }

                            Button {
                                editingListId = list.id
                                editingListName = list.name
                                showEditListAlert = true
                            } label: {
                                Label("名前変更", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("ToDoリスト")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("リスト名を変更", isPresented: $showEditListAlert) {
                TextField("リスト名", text: $editingListName)
                Button("保存") {
                    if let id = editingListId {
                        store.renameList(id, to: editingListName)
                        selectedListId = id
                    }
                    editingListId = nil
                    editingListName = ""
                }
                Button("キャンセル", role: .cancel) {
                    editingListId = nil
                    editingListName = ""
                }
            }
            .confirmationDialog(
                "リストを削除しますか？（中のToDoも削除されます）",
                isPresented: $showDeleteListDialog,
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    if let list = deleteListCandidate {
                        let deletingSelected = (list.id == effectiveSelectedId)
                        store.deleteList(list.id)
                        if deletingSelected {
                            selectedListId = store.defaultListId()
                        }
                    }
                    deleteListCandidate = nil
                }
                Button("キャンセル", role: .cancel) {
                    deleteListCandidate = nil
                }
            }
        }
    }
}

private struct MemoTodoListTab: View {
    let name: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let bg = isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)
        let border = isSelected ? Color.accentColor : Color.clear

        Text(name)
            .font(.subheadline)
            .lineLimit(1)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(bg)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(border, lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture { onSelect() }
            .contextMenu {
                Button {
                    onRename()
                } label: {
                    Label("名前変更", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
    }
}
