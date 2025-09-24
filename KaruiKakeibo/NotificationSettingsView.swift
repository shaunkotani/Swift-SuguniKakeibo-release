import SwiftUI

struct NotificationSettingsView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingPermissionAlert = false
    @State private var showingTestAlert = false
    @State private var showingAddTimeSheet = false
    @State private var showingEditTimeSheet = false
    @State private var editingTimeIndex: Int = 0
    @State private var permissionAlertType: PermissionAlertType = .initial
    
    enum PermissionAlertType {
        case initial      // 初回権限要求
        case denied       // 権限拒否後の設定画面誘導
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 通知の有効/無効
                Section(header: Text("通知設定")) {
                    Toggle("通知を有効にする", isOn: Binding(
                        get: { notificationManager.isNotificationEnabled },
                        set: { newValue in
                            if newValue && !notificationManager.hasPermission {
                                notificationManager.getNotificationStatus { status in
                                    if status == .notDetermined {
                                        // 初回要求
                                        notificationManager.toggleNotification(newValue) { granted, needsSettings in
                                            if needsSettings {
                                                permissionAlertType = .denied
                                                showingPermissionAlert = true
                                            }
                                        }
                                    } else {
                                        // 既に拒否されている場合
                                        permissionAlertType = .denied
                                        showingPermissionAlert = true
                                    }
                                }
                            } else {
                                notificationManager.toggleNotification(newValue) { _, _ in }
                            }
                        }
                    ))
                    
                    if notificationManager.isNotificationEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("設定済み通知: \(notificationManager.enabledNotificationCount)件")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text("毎日指定した時刻にリマインダー通知を送信します")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // 通知時刻一覧
                if notificationManager.isNotificationEnabled {
                    Section(header: 
                        HStack {
                            Text("通知時刻")
                            Spacer()
                            Button(action: {
                                showingAddTimeSheet = true
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                            }
                        }
                    ) {
                        if notificationManager.notificationTimes.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                Text("通知時刻が設定されていません")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                Button("時刻を追加") {
                                    showingAddTimeSheet = true
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            ForEach(Array(notificationManager.notificationTimes.enumerated()), id: \.element.id) { index, time in
                                NotificationTimeRow(
                                    time: time,
                                    onToggle: {
                                        notificationManager.toggleNotificationTime(at: index)
                                    },
                                    onEdit: {
                                        editingTimeIndex = index
                                        showingEditTimeSheet = true
                                    },
                                    onDelete: {
                                        notificationManager.removeNotificationTime(at: index)
                                    }
                                )
                            }
                            
                            // リセットボタン
                            if notificationManager.notificationTimes.count > 1 {
                                Button(action: {
                                    notificationManager.resetToDefaultTime()
                                }) {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                            .foregroundColor(.orange)
                                        Text("デフォルト時刻にリセット")
                                            .foregroundColor(.orange)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                
                // 権限状態の表示
                Section(header: Text("権限状態")) {
                    HStack {
                        Image(systemName: notificationManager.hasPermission ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(notificationManager.hasPermission ? .green : .red)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("通知権限")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(notificationManager.hasPermission ? "許可されています" : "許可されていません")
                                .font(.caption)
                                .foregroundColor(notificationManager.hasPermission ? .green : .red)
                        }
                        
                        Spacer()
                        
                        if !notificationManager.hasPermission {
                            Button("権限を要求") {
                                notificationManager.getNotificationStatus { status in
                                    if status == .notDetermined {
                                        // 初回要求
                                        notificationManager.requestPermission { granted, needsSettings in
                                            if needsSettings {
                                                permissionAlertType = .denied
                                                showingPermissionAlert = true
                                            }
                                        }
                                    } else {
                                        // 既に拒否されている場合
                                        permissionAlertType = .denied
                                        showingPermissionAlert = true
                                    }
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // テスト通知
                if notificationManager.hasPermission {
                    Section(header: Text("テスト")) {
                        Button(action: {
                            notificationManager.sendTestNotification()
                            showingTestAlert = true
                        }) {
                            HStack {
                                Image(systemName: "bell.badge")
                                    .foregroundColor(.orange)
                                Text("テスト通知を送信")
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        Text("3秒後にテスト通知が届きます")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 通知内容のプレビュー
                Section(header: Text("通知内容プレビュー")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "app.badge")
                                .foregroundColor(.blue)
                            Text("軽い家計簿")
                                .fontWeight(.medium)
                            Spacer()
                            Text("今すぐ")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("支出の記録")
                                .fontWeight(.semibold)
                            Text("今日の支出記録を忘れていませんか？💰")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // 説明セクション
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("通知について")
                                .fontWeight(.medium)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• 複数の時刻を設定できます")
                            Text("• 各通知は個別にオン/オフできます")
                            Text("• 毎日設定した時刻にリマインダーが届きます")
                            Text("• 支出記録を習慣化するのに役立ちます")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("通知設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完了") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                notificationManager.checkPermission()
            }
            .alert("通知権限について", isPresented: $showingPermissionAlert) {
                switch permissionAlertType {
                case .initial:
                    Button("設定で許可") {
                        notificationManager.openSettings()
                    }
                    Button("キャンセル") { }
                case .denied:
                    Button("設定を開く") {
                        notificationManager.openSettings()
                    }
                    Button("後で") { }
                }
            } message: {
                switch permissionAlertType {
                case .initial:
                    Text("通知を有効にするには、設定アプリで通知を許可してください。")
                case .denied:
                    Text("通知権限が拒否されています。設定アプリの「軽い家計簿」→「通知」で許可してください。")
                }
            }
            .alert("テスト通知を送信しました", isPresented: $showingTestAlert) {
                Button("OK") { }
            } message: {
                Text("3秒後にテスト通知が届きます。届かない場合は通知設定を確認してください。")
            }
            .sheet(isPresented: $showingAddTimeSheet) {
                AddNotificationTimeView()
            }
            .sheet(isPresented: $showingEditTimeSheet) {
                EditNotificationTimeView(timeIndex: editingTimeIndex)
            }
        }
    }
}

// MARK: - 通知時刻行ビュー
struct NotificationTimeRow: View {
    let time: NotificationTime
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isEnabled: Bool
    
    init(time: NotificationTime, onToggle: @escaping () -> Void, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.time = time
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.onDelete = onDelete
        self._isEnabled = State(initialValue: time.isEnabled)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // 有効/無効切り替え
            Toggle("", isOn: $isEnabled)
                .onChange(of: isEnabled) { _ in
                    onToggle()
                }
                .labelsHidden()
            
            // 時刻表示
            VStack(alignment: .leading, spacing: 2) {
                Text(time.displayTime)
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(time.isEnabled ? .primary : .secondary)
                
                Text(time.isEnabled ? "有効" : "無効")
                    .font(.caption)
                    .foregroundColor(time.isEnabled ? .green : .gray)
            }
            
            Spacer()
            
            // 編集・削除ボタン
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                        .font(.subheadline)
                }
                
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
        .onChange(of: time.isEnabled) { newValue in
            isEnabled = newValue
        }
    }
}

// MARK: - 通知時刻追加ビュー
struct AddNotificationTimeView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("新しい通知時刻")) {
                    DatePicker(
                        "時刻を選択",
                        selection: $selectedDate,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                }
                
                Section {
                    Button("追加") {
                        let calendar = Calendar.current
                        let hour = calendar.component(.hour, from: selectedDate)
                        let minute = calendar.component(.minute, from: selectedDate)
                        
                        notificationManager.addNotificationTime(hour: hour, minute: minute)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("通知時刻を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 通知時刻編集ビュー
struct EditNotificationTimeView: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate = Date()
    let timeIndex: Int
    
    var body: some View {
        NavigationStack {
            Form {
                if timeIndex < notificationManager.notificationTimes.count {
                    Section(header: Text("通知時刻を編集")) {
                        DatePicker(
                            "時刻を選択",
                            selection: $selectedDate,
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.wheel)
                    }
                    
                    Section {
                        Button("保存") {
                            let calendar = Calendar.current
                            let hour = calendar.component(.hour, from: selectedDate)
                            let minute = calendar.component(.minute, from: selectedDate)
                            
                            notificationManager.updateNotificationTime(at: timeIndex, hour: hour, minute: minute)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }
            .navigationTitle("通知時刻を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if timeIndex < notificationManager.notificationTimes.count {
                    let time = notificationManager.notificationTimes[timeIndex]
                    let calendar = Calendar.current
                    let components = DateComponents(hour: time.hour, minute: time.minute)
                    selectedDate = calendar.date(from: components) ?? Date()
                }
            }
        }
    }
}

struct NotificationSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettingsView()
    }
}