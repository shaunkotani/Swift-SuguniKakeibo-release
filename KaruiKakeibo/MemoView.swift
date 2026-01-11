import SwiftUI

struct MemoView: View {
    @StateObject private var store = MemoStore()

    @State private var newShopping = ""
    @State private var newSavingsTodo = ""
    @State private var newGeneral = ""

    @State private var editingTodoId: UUID? = nil
    @State private var editingTitle: String = ""
    @State private var showEditAlert = false

    // キーボード制御（タップ or スクロールで閉じる）
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case memo
        case shopping
        case savingsAmount
        case savingsTodo
        case generalTodo
        case editTitle
    }

    private func dismissKeyboard() {
        focusedField = nil
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

            // 買い物リスト
            todoSection(
                title: "買い物リスト",
                kind: .shopping,
                newText: $newShopping,
                placeholder: "例）牛乳、米、洗剤",
                addAction: {
                    store.addTodo(title: newShopping, kind: .shopping)
                    newShopping = ""
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            )

            // 毎月の貯金チェック
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

            // 貯金ToDo（任意）
            todoSection(
                title: "貯金ToDo（任意）",
                kind: .savings,
                newText: $newSavingsTodo,
                placeholder: "例）NISA入金、積立設定の確認",
                addAction: {
                    store.addTodo(title: newSavingsTodo, kind: .savings)
                    newSavingsTodo = ""
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            )

            // その他ToDo
            todoSection(
                title: "その他ToDo",
                kind: .general,
                newText: $newGeneral,
                placeholder: "例）家賃更新、クレカ見直し",
                addAction: {
                    store.addTodo(title: newGeneral, kind: .general)
                    newGeneral = ""
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            )
        }
        .scrollDismissesKeyboard(.interactively)
        // 画面タップでキーボードを閉じる（他のタップ操作を邪魔しない）
        .simultaneousGesture(
            TapGesture().onEnded { dismissKeyboard() }
        )
        .navigationTitle("メモ")
        .alert("ToDoを編集", isPresented: $showEditAlert) {
            TextField("内容", text: $editingTitle)
                .focused($focusedField, equals: .editTitle)
            Button("保存") {
                if let id = editingTodoId {
                    store.updateTodoTitle(id, title: editingTitle)
                }
                editingTodoId = nil
                editingTitle = ""
            }
            Button("キャンセル", role: .cancel) {
                editingTodoId = nil
                editingTitle = ""
            }
        }
    }

    // MARK: - Todo Section Builder
    @ViewBuilder
    private func todoSection(
        title: String,
        kind: TodoKind,
        newText: Binding<String>,
        placeholder: String,
        addAction: @escaping () -> Void
    ) -> some View {
        Section(header: Text(title)) {
            HStack(spacing: 12) {
                TextField(placeholder, text: newText)
                    .textInputAutocapitalization(.never)
                    .focused($focusedField, equals: kind == .shopping ? .shopping : (kind == .savings ? .savingsTodo : .generalTodo))

                Button("追加") { addAction() }
                    .disabled(newText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            let items = store.todos(of: kind)
            if items.isEmpty {
                Text("未登録")
                    .foregroundColor(.secondary)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 12) {
                        Button {
                            store.toggleTodo(item.id)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)

                        Text(item.title)
                            .strikethrough(item.isDone)
                            .foregroundColor(item.isDone ? .secondary : .primary)

                        Spacer()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.deleteTodo(item.id)
                        } label: {
                            Label("削除", systemImage: "trash")
                        }

                        Button {
                            editingTodoId = item.id
                            editingTitle = item.title
                            showEditAlert = true
                        } label: {
                            Label("編集", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
    }
}
