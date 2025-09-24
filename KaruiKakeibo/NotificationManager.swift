import Foundation
import UserNotifications
import SwiftUI

// 通知時刻の構造体
struct NotificationTime: Codable, Identifiable {
    let id = UUID()
    let hour: Int
    let minute: Int
    let isEnabled: Bool
    
    var displayTime: String {
        return String(format: "%02d:%02d", hour, minute)
    }
    
    var dateComponents: DateComponents {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return components
    }
}

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var hasPermission = false
    @Published var isNotificationEnabled = UserDefaults.standard.bool(forKey: "isNotificationEnabled")
    @Published var notificationTimes: [NotificationTime] = []
    
    private init() {
        loadNotificationTimes()
        checkPermission()
    }
    
    // 通知時刻データの読み込み
    private func loadNotificationTimes() {
        if let data = UserDefaults.standard.data(forKey: "notificationTimes"),
           let times = try? JSONDecoder().decode([NotificationTime].self, from: data) {
            notificationTimes = times
        } else {
            // デフォルト時刻（20:00）を設定
            notificationTimes = [NotificationTime(hour: 20, minute: 0, isEnabled: true)]
            saveNotificationTimes()
        }
    }
    
    // 通知時刻データの保存
    private func saveNotificationTimes() {
        if let data = try? JSONEncoder().encode(notificationTimes) {
            UserDefaults.standard.set(data, forKey: "notificationTimes")
        }
    }
    
    // 通知権限の確認
    func checkPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.hasPermission = settings.authorizationStatus == .authorized
            }
        }
    }
    
    // 通知権限の状態を詳細に確認
    func getNotificationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }
    
    // 通知権限の要求
    func requestPermission(completion: @escaping (Bool, Bool) -> Void = { _, _ in }) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                // 既に許可済みの場合
                if settings.authorizationStatus == .authorized {
                    self.hasPermission = true
                    completion(true, false) // (許可済み, 設定画面に誘導する必要なし)
                    return
                }
                
                // 初回要求の場合（notDetermined）
                if settings.authorizationStatus == .notDetermined {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                        DispatchQueue.main.async {
                            self.hasPermission = granted
                            if granted {
                                print("📱 通知権限が許可されました")
                                completion(true, false)
                            } else {
                                print("📱 通知権限が拒否されました")
                                completion(false, true) // 設定画面に誘導
                            }
                        }
                    }
                } else {
                    // 既に拒否されている場合（denied）
                    print("📱 通知権限が既に拒否されています。設定画面での変更が必要です。")
                    completion(false, true) // 設定画面に誘導
                }
            }
        }
    }
    
    // 設定画面を開く
    func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    // 通知のスケジューリング
    func scheduleNotifications() {
        guard hasPermission && isNotificationEnabled else {
            print("📱 通知権限がないか、通知が無効です")
            return
        }
        
        // 既存の通知をすべてキャンセル
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        // 有効な通知時刻のみスケジュール
        let enabledTimes = notificationTimes.filter { $0.isEnabled }
        
        for (index, time) in enabledTimes.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "支出の記録"
            content.body = "今日の支出記録を忘れていませんか？💰"
            content.sound = .default
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: time.dateComponents, repeats: true)
            
            let request = UNNotificationRequest(
                identifier: "dailyExpenseReminder_\(index)",
                content: content,
                trigger: trigger
            )
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("📱 通知のスケジュール失敗 (\(time.displayTime)): \(error.localizedDescription)")
                } else {
                    print("📱 毎日\(time.displayTime)に通知をスケジュールしました")
                }
            }
        }
        
        if enabledTimes.isEmpty {
            print("📱 有効な通知時刻がありません")
        }
    }
    
    // 通知のキャンセル
    func cancelNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        print("📱 すべての通知をキャンセルしました")
    }
    
    // 通知有効/無効の切り替え
    func toggleNotification(_ enabled: Bool, completion: @escaping (Bool, Bool) -> Void = { _, _ in }) {
        isNotificationEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "isNotificationEnabled")
        
        if enabled {
            if hasPermission {
                scheduleNotifications()
                completion(true, false)
            } else {
                requestPermission { granted, needsSettings in
                    if granted {
                        self.scheduleNotifications()
                    }
                    completion(granted, needsSettings)
                }
            }
        } else {
            cancelNotifications()
            completion(true, false)
        }
    }
    
    // 新しい通知時刻を追加
    func addNotificationTime(hour: Int, minute: Int) {
        let newTime = NotificationTime(hour: hour, minute: minute, isEnabled: true)
        notificationTimes.append(newTime)
        saveNotificationTimes()
        
        // 通知が有効な場合は再スケジュール
        if isNotificationEnabled && hasPermission {
            scheduleNotifications()
        }
        
        print("📱 通知時刻を追加しました: \(newTime.displayTime)")
    }
    
    // 通知時刻を削除
    func removeNotificationTime(at index: Int) {
        guard index >= 0 && index < notificationTimes.count else { return }
        
        let removedTime = notificationTimes[index]
        notificationTimes.remove(at: index)
        saveNotificationTimes()
        
        // 通知が有効な場合は再スケジュール
        if isNotificationEnabled && hasPermission {
            scheduleNotifications()
        }
        
        print("📱 通知時刻を削除しました: \(removedTime.displayTime)")
    }
    
    // 通知時刻の有効/無効を切り替え
    func toggleNotificationTime(at index: Int) {
        guard index >= 0 && index < notificationTimes.count else { return }
        
        let oldTime = notificationTimes[index]
        notificationTimes[index] = NotificationTime(
            hour: oldTime.hour,
            minute: oldTime.minute,
            isEnabled: !oldTime.isEnabled
        )
        saveNotificationTimes()
        
        // 通知が有効な場合は再スケジュール
        if isNotificationEnabled && hasPermission {
            scheduleNotifications()
        }
        
        let status = notificationTimes[index].isEnabled ? "有効" : "無効"
        print("📱 通知時刻(\(notificationTimes[index].displayTime))を\(status)にしました")
    }
    
    // 通知時刻を更新
    func updateNotificationTime(at index: Int, hour: Int, minute: Int) {
        guard index >= 0 && index < notificationTimes.count else { return }
        
        let oldTime = notificationTimes[index]
        notificationTimes[index] = NotificationTime(
            hour: hour,
            minute: minute,
            isEnabled: oldTime.isEnabled
        )
        saveNotificationTimes()
        
        // 通知が有効な場合は再スケジュール
        if isNotificationEnabled && hasPermission {
            scheduleNotifications()
        }
        
        print("📱 通知時刻を更新しました: \(notificationTimes[index].displayTime)")
    }
    
    // デフォルト通知時刻にリセット
    func resetToDefaultTime() {
        notificationTimes = [NotificationTime(hour: 20, minute: 0, isEnabled: true)]
        saveNotificationTimes()
        
        // 通知が有効な場合は再スケジュール
        if isNotificationEnabled && hasPermission {
            scheduleNotifications()
        }
        
        print("📱 通知時刻をデフォルト(20:00)にリセットしました")
    }
    
    // 有効な通知時刻の数を取得
    var enabledNotificationCount: Int {
        return notificationTimes.filter { $0.isEnabled }.count
    }
    
    // テスト通知（開発用）
    func sendTestNotification() {
        guard hasPermission else {
            print("📱 通知権限がありません")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "テスト通知"
        content.body = "通知設定が正常に動作しています ✅"
        content.sound = .default
        
        // 3秒後にトリガー
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "testNotification",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("📱 テスト通知の送信失敗: \(error.localizedDescription)")
            } else {
                print("📱 3秒後にテスト通知を送信します")
            }
        }
    }
}