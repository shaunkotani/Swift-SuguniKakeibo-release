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
    case category = 1
    case input = 2
    case expenses = 3
    case settings = 4
    
    var title: String {
        switch self {
        case .calendar: return "日別集計"
        case .category: return "カテゴリ集計"
        case .input: return "入力"
        case .expenses: return "履歴と編集"
        case .settings: return "設定"
        }
    }
    
    var systemImage: String {
        switch self {
        case .calendar: return "calendar"
        case .category: return "chart.pie"
        case .input: return "plus.circle"
        case .expenses: return "list.bullet"
        case .settings: return "gear"
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ExpenseViewModel()
    @State private var shouldFocusAmount: Bool = false
    @State private var selectedTab: Int = AppTab.input.rawValue
    
    var body: some View {
        TabBarControllerRepresentable(
            calendarView: AnyView(CalendarView(
                selectedTab: $selectedTab,
                shouldFocusAmount: $shouldFocusAmount
            ).environmentObject(viewModel)),
            
            categoryView: AnyView(CategorySummaryView(
                selectedTab: $selectedTab,
                shouldFocusAmount: $shouldFocusAmount
            ).environmentObject(viewModel)),
            
            inputView: AnyView(InputView(
                shouldFocusAmount: $shouldFocusAmount
            ).environmentObject(viewModel)),
            
            expensesView: AnyView(ExpensesView()
                .environmentObject(viewModel)),
            
            settingsView: AnyView(SettingView()
                .environmentObject(viewModel))
        )
//        .ignoresSafeArea(.keyboard, edges: .bottom)
        .edgesIgnoringSafeArea(.all)
    }
    
    // 他のビューから呼び出せる関数（既存機能を維持）
    func navigateToInputWithFocus() {
        // 入力タブに切り替え
        selectedTab = AppTab.input.rawValue
        
        // 少し遅延してからフォーカス
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldFocusAmount = true
        }
        
        print("📱 支出追加ボタンから入力画面へ遷移")
    }
}

// MARK: - UIKit ラッパー（UITabBarControllerDelegate で再選択検知）
struct TabBarControllerRepresentable: UIViewControllerRepresentable {
    let calendarView: AnyView
    let categoryView: AnyView
    let inputView: AnyView
    let expensesView: AnyView
    let settingsView: AnyView
    
    func makeUIViewController(context: Context) -> UITabBarController {
        let tabBarController = UITabBarController()
        tabBarController.delegate = context.coordinator
        
        // TabBarの外観をLiquid Glass対応（iOS 26+）/ ブラー（iOS 25以下）に設定
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        
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
        
        let categoryVC = UIHostingController(rootView: categoryView)
        categoryVC.tabBarItem = UITabBarItem(
            title: AppTab.category.title,
            image: UIImage(systemName: AppTab.category.systemImage),
            tag: AppTab.category.rawValue
        )
        
        let inputVC = UIHostingController(rootView: inputView)
        inputVC.tabBarItem = UITabBarItem(
            title: AppTab.input.title,
            image: UIImage(systemName: AppTab.input.systemImage),
            tag: AppTab.input.rawValue
        )
        
        let expensesVC = UIHostingController(rootView: expensesView)
        expensesVC.tabBarItem = UITabBarItem(
            title: AppTab.expenses.title,
            image: UIImage(systemName: AppTab.expenses.systemImage),
            tag: AppTab.expenses.rawValue
        )
        
        let settingsVC = UIHostingController(rootView: settingsView)
        settingsVC.tabBarItem = UITabBarItem(
            title: AppTab.settings.title,
            image: UIImage(systemName: AppTab.settings.systemImage),
            tag: AppTab.settings.rawValue
        )
        
        tabBarController.viewControllers = [
            calendarVC, categoryVC, inputVC, expensesVC, settingsVC
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
        
        print("✅ UITabBarController 設定完了")
        return tabBarController
    }
    
    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {
        // 必要に応じて動的更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: Coordinator = UITabBarControllerDelegate 実装
    final class Coordinator: NSObject, UITabBarControllerDelegate {
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
                
                // 🆕 タブ別の再選択時ハプティックフィードバック
                //                generateTabReselectionHaptic(for: newIndex)
                if newIndex == 2 || newIndex == 3 {
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
                
                // 🆕 タブ別の選択時ハプティックフィードバック
//                generateTabSelectionHaptic(for: newIndex)
                
            }
            
            return true // 選択自体は許可
        }
        
        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            if let index = tabBarController.viewControllers?.firstIndex(where: { $0 === viewController }) {
                print("🏷️ タブ選択完了: index \(index)")
                // 選択完了時の処理（必要に応じて）
//                generateTabSelectionCompleteHaptic(for: index)
            }
        }
        // 🆕 タブ再選択時のハプティックフィードバック
        private func generateTabReselectionHaptic(for index: Int) {
            switch index {
            case 0: // カレンダータブ
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                print("📅 カレンダータブ再選択 - medium haptic")
                
            case 1: // カテゴリ集計タブ
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                print("📊 カテゴリ集計タブ再選択 - medium haptic")
                
            case 2: // 入力タブ
                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.impactOccurred()
                print("💰 入力タブ再選択 - heavy haptic")
                
            case 3: // 履歴タブ
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                print("📋 履歴タブ再選択 - medium haptic")
                
            case 4: // 設定タブ
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                print("⚙️ 設定タブ再選択 - light haptic")
                
            default:
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
        // 🆕 通常のタブ選択時のハプティックフィードバック
        private func generateTabSelectionHaptic(for index: Int) {
            switch index {
            case 0: // カレンダータブ
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                print("📅 カレンダータブ選択 - light haptic")
                
            case 1: // カテゴリ集計タブ
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                print("📊 カテゴリ集計タブ選択 - light haptic")
                
            case 2: // 入力タブ
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                print("💰 入力タブ選択 - medium haptic")
                
            case 3: // 履歴タブ
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                print("📋 履歴タブ選択 - light haptic")
                
            case 4: // 設定タブ
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                print("⚙️ 設定タブ選択 - light haptic")
                
            default:
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
        // 🆕 選択完了時のハプティックフィードバック（オプション）
        private func generateTabSelectionCompleteHaptic(for index: Int) {
            // より細かい制御が必要な場合のみ使用
            // 例：特定のタブでのみ追加フィードバック
            if index == 2 { // 入力タブの場合のみ
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let selectionFeedback = UISelectionFeedbackGenerator()
                    selectionFeedback.selectionChanged()
                    print("💰 入力タブ選択完了 - selection feedback")
                }
            }
        }
    }
}

