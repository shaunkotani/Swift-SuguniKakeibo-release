import Foundation
import Combine

enum TodoKind: String, Codable, CaseIterable, Identifiable {
    case shopping   // 買い物
    case savings    // 貯金（任意のToDo）
    case general    // その他

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shopping: return "買い物リスト"
        case .savings:  return "貯金ToDo"
        case .general:  return "その他ToDo"
        }
    }
}

struct TodoItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var isDone: Bool = false
    var kind: TodoKind
    var createdAt: Date = Date()
    var doneAt: Date? = nil
}

final class MemoStore: ObservableObject {
    // MARK: - Keys
    private let memoKey = "memo.freeText.v1"
    private let todosKey = "memo.todos.v1"
    private let savingsTargetKey = "memo.savingsTargetAmount.v1"
    private let savingsCheckedKey = "memo.savingsChecked.v1"
    private let savingsCheckedMonthKey = "memo.savingsCheckedMonth.v1"

    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Published
    @Published var freeMemo: String = ""
    @Published var todos: [TodoItem] = []

    // 「毎月の貯金チェック」
    @Published var savingsTargetAmount: Double = 0
    @Published var savingsCheckedThisMonth: Bool = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        rolloverSavingsIfNeeded()
        setupAutosave()
    }

    // MARK: - Public actions
    func addTodo(title: String, kind: TodoKind) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todos.insert(TodoItem(title: trimmed, kind: kind), at: 0)
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

    func todos(of kind: TodoKind) -> [TodoItem] {
        todos.filter { $0.kind == kind }
    }

    // MARK: - Savings monthly rollover
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
            // 月が変わったらチェックをリセット
            savingsCheckedThisMonth = false
            defaults.set(current, forKey: savingsCheckedMonthKey)
        }
    }

    // MARK: - Load / Save
    private func load() {
        freeMemo = defaults.string(forKey: memoKey) ?? ""

        if let data = defaults.data(forKey: todosKey) {
            do {
                todos = try JSONDecoder().decode([TodoItem].self, from: data)
            } catch {
                todos = []
            }
        } else {
            todos = []
        }

        savingsTargetAmount = defaults.double(forKey: savingsTargetKey)
        savingsCheckedThisMonth = defaults.bool(forKey: savingsCheckedKey)
    }

    private func setupAutosave() {
        // メモ：軽くデバウンスして保存
        $freeMemo
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.defaults.set(text, forKey: self?.memoKey ?? "")
            }
            .store(in: &cancellables)

        // todos：変更毎に保存（小規模を想定）
        $todos
            .dropFirst()
            .sink { [weak self] items in
                guard let self else { return }
                do {
                    let data = try JSONEncoder().encode(items)
                    self.defaults.set(data, forKey: self.todosKey)
                } catch {
                    // 失敗時は無視（必要ならログ）
                }
            }
            .store(in: &cancellables)

        $savingsTargetAmount
            .dropFirst()
            .sink { [weak self] v in
                self?.defaults.set(v, forKey: self?.savingsTargetKey ?? "")
            }
            .store(in: &cancellables)

        $savingsCheckedThisMonth
            .dropFirst()
            .sink { [weak self] v in
                self?.defaults.set(v, forKey: self?.savingsCheckedKey ?? "")
            }
            .store(in: &cancellables)
    }
}
