//
//  ContentView.swift (UITabBarController再選択対応版 - 修正版)
//  家計簿アプリ

import SwiftUI
import UIKit

// MARK: - 通知名（再選択イベントをSwiftUIに伝える）
extension Notification.Name {
    static let tabReselected = Notification.Name("TabReselectedNotification")
    static let switchTab = Notification.Name("SwitchTabNotification")
}

// MARK: - タブ識別子
enum AppTab: Int, CaseIterable {
    case calendar = 0
    case analysis = 1
    case input = 2
    case memo = 3
    case calculator = 4

    var title: String {
        switch self {
        case .calendar: return "カレンダー"
        case .analysis: return "分析"
        case .input: return "入力"
        case .memo: return "メモ"
        case .calculator: return "電卓"
        }
    }

    var systemImage: String {
        switch self {
        case .calendar: return "calendar"
        case .analysis: return "chart.bar"
        case .input: return "plus.circle"
        case .memo: return "note.text"
        case .calculator: return "x.squareroot"
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ExpenseViewModel()

    @State private var selectedTab: Int = AppTab.input.rawValue
    @State private var shouldFocusAmount: Bool = false

    var body: some View {
        TabBarControllerRepresentable(
            calendarView: AnyView(
                CalendarView(
                    selectedTab: $selectedTab,
                    shouldFocusAmount: $shouldFocusAmount
                )
                .environmentObject(viewModel)
                .withOverflowMenu()
            ),

            analysisView: AnyView(
                AnalysisView()
                    .environmentObject(viewModel)
                    .withOverflowMenu()
            ),

            inputView: AnyView(
                InputView(
                    shouldFocusAmount: $shouldFocusAmount
                )
                .environmentObject(viewModel)
                .withOverflowMenu()
            ),

            memoView: AnyView(
                MemoView()
            ),

            calculatorView: AnyView(
                CalculatorPlaceholderView()
            )
        )
        .edgesIgnoringSafeArea(.all)
    }
}

struct TabBarControllerRepresentable: UIViewControllerRepresentable {
    let calendarView: AnyView
    let analysisView: AnyView
    let inputView: AnyView
    let memoView: AnyView
    let calculatorView: AnyView

    func makeUIViewController(context: Context) -> UITabBarController {
        let tabBarController = UITabBarController()
        tabBarController.delegate = context.coordinator

        // TabBarの外観をLiquid Glass対応（iOS 26+）/ ブラー（iOS 25以下）に設定
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear

        // すべてのOSバージョンで安定したブラー背景を使用
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)

        // 半透明を有効化
        tabBarController.tabBar.isTranslucent = true

        // 標準/スクロールエッジの両方に適用
        tabBarController.tabBar.standardAppearance = appearance
        tabBarController.tabBar.scrollEdgeAppearance = appearance
        tabBarController.tabBar.backgroundColor = .clear

        // iOS 26 以降のみ、ガラスエフェクトを下地に敷く
        // Removed per instructions

        // 各タブをUIHostingControllerでラップ
        let calendarVC = UIHostingController(rootView: calendarView)
        calendarVC.tabBarItem = UITabBarItem(
            title: AppTab.calendar.title,
            image: UIImage(systemName: AppTab.calendar.systemImage),
            tag: AppTab.calendar.rawValue
        )

        let analysisVC = UIHostingController(rootView: analysisView)
        analysisVC.tabBarItem = UITabBarItem(
            title: AppTab.analysis.title,
            image: UIImage(systemName: AppTab.analysis.systemImage),
            tag: AppTab.analysis.rawValue
        )

        let inputVC = UIHostingController(rootView: inputView)
        inputVC.tabBarItem = UITabBarItem(
            title: AppTab.input.title,
            image: UIImage(systemName: AppTab.input.systemImage),
            tag: AppTab.input.rawValue
        )

        let memoVC = UIHostingController(rootView: memoView)
        memoVC.tabBarItem = UITabBarItem(
            title: AppTab.memo.title,
            image: UIImage(systemName: AppTab.memo.systemImage),
            tag: AppTab.memo.rawValue
        )

        let calculatorVC = UIHostingController(rootView: calculatorView)
        calculatorVC.tabBarItem = UITabBarItem(
            title: AppTab.calculator.title,
            image: UIImage(systemName: AppTab.calculator.systemImage),
            tag: AppTab.calculator.rawValue
        )

        tabBarController.viewControllers = [
            calendarVC, analysisVC, inputVC, memoVC, calculatorVC
        ]

        // デフォルトで入力タブを選択
        tabBarController.selectedIndex = AppTab.input.rawValue

        // 🔔 タブ切替通知を監視してプログラム的にタブを切り替え
        NotificationCenter.default.addObserver(forName: .switchTab, object: nil, queue: .main) { notification in
            if let index = notification.userInfo?["index"] as? Int,
               index >= 0,
               let viewControllers = tabBarController.viewControllers,
               index < viewControllers.count {
                tabBarController.selectedIndex = index
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
            }
        }

        print("✅ UITabBarController Completed!")
        return tabBarController
    }

    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UITabBarControllerDelegate {
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            print("🔄 shouldSelect 呼び出し")

            // インデックスを取得
            guard let viewControllers = tabBarController.viewControllers,
                  let newIndex = viewControllers.firstIndex(where: { $0 === viewController }) else {
                return true
            }

            // 現在選択中のVCと、これから選択しようとしているVCが同一なら「再選択」
            if tabBarController.selectedViewController === viewController {
                print("🔥 タブ再選択を検出")
                print("📱 再選択されたタブインデックス: \(newIndex)")

                // 入力タブだけ強め（必要なら後で調整）
                if newIndex == AppTab.input.rawValue {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                    impactFeedback.impactOccurred()
                }

                // 通知を送信
                NotificationCenter.default.post(
                    name: .tabReselected,
                    object: nil,
                    userInfo: ["index": newIndex]
                )
            } else {
                print("🔄 通常のタブ選択")
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
            }

            return true // 選択自体は許可
        }

        // （未使用だが将来の調整用に残置）
        private func generateTabReselectionHaptic(for index: Int) {
            switch index {
            case 0:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case 1:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case 2:
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            default:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        private func generateTabSelectionHaptic(for index: Int) {
            switch index {
            case 0:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case 1:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case 2:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            default:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}

// MARK: - 右上「…」メニュー（CSV / iOS設定）
private enum AppMenuActions {
    static func exportCSV() {
        // TODO: CSVエクスポート画面に接続（いったん仮実装）
        print("🧾 CSVエクスポート（仮）")
    }

    static func importCSV() {
        // TODO: CSVインポート画面に接続（いったん仮実装）
        print("📥 CSVインポート（仮）")
    }

    static func openIOSSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct OverflowMenu: View {
    var body: some View {
        Menu {
            Button("CSVエクスポート") { AppMenuActions.exportCSV() }
            Button("CSVインポート") { AppMenuActions.importCSV() }
            Divider()
            Button("iOS設定を開く") { AppMenuActions.openIOSSettings() }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("メニュー")
    }
}

private struct OverflowMenuToolbar: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                OverflowMenu()
            }
        }
    }
}

private extension View {
    /// NavigationStack内で使う前提（右上に「…」メニューを追加）
    func withOverflowMenu() -> some View {
        self.modifier(OverflowMenuToolbar())
    }
}

// MARK: - 分析タブ（暫定：既存Viewを壊さず接続するためのプレースホルダ）
private struct AnalysisPlaceholderView: View {
    @Binding var selectedTab: Int
    @Binding var shouldFocusAmount: Bool
    @EnvironmentObject var viewModel: ExpenseViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("分析（準備中）") {
                    Text("今後ここにトップビュー / 月間推移 / 年間推移などを追加します。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("既存機能へのリンク") {
                    NavigationLink("カテゴリ別集計") {
                        CategorySummaryView(
                            selectedTab: $selectedTab,
                            shouldFocusAmount: $shouldFocusAmount
                        )
                        .environmentObject(viewModel)
                    }

                    NavigationLink("支出の履歴") {
                        ExpensesView()
                            .environmentObject(viewModel)
                    }
                }
            }
            .navigationTitle("分析")
        }
    }
}

// MARK: - メモ / 電卓（暫定プレースホルダ）
private struct MemoPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "note.text")
                    .font(.system(size: 40))
                Text("メモ（準備中）")
                    .font(.headline)
                Text("お買い物メモや注意点などをここに追加予定です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("メモ")
        }
    }
}

private struct CalculatorPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "calculator")
                    .font(.system(size: 40))
                Text("電卓（準備中）")
                    .font(.headline)
                Text("家計計算に特化した電卓をここに追加予定です。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("電卓")
        }
    }
}

