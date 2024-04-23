import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var cameraController = CameraController()
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingSheet = false
    @State private var serverURLs: [String] = UserDefaults.standard.stringArray(forKey: "serverURLs") ?? []
    @State private var selectedURLIndex = 0


    var body: some View {
        VStack {
            if !serverURLs.isEmpty {
                Picker("選択してください", selection: $selectedURLIndex) {
                    ForEach(0..<serverURLs.count, id: \.self) {
                        Text(self.serverURLs[$0])
                    }
                }
                .onChange(of: selectedURLIndex) { newIndex in
                    UserDefaults.standard.set(self.serverURLs[newIndex], forKey: "currentServerURL")
                }
            }
            
            if let previewLayer = cameraController.previewLayer {
                CameraPreview(previewLayer: previewLayer)
                    .frame(height: 300)
                    .overlay(
                        BarcodeOverlay()
                    )
            } else {
                Text("カメラの準備中...")
            }
            if let scannedBooks = cameraController.scannedBooks {
                ISBNListView(scannedBooks: scannedBooks)
            }
            Spacer()
            HStack(spacing: 20) {  // ボタンを水平に並べる
                Button(action: {
                    if cameraController.isCameraRunning {
                        cameraController.stopRunning()
                    } else {
                        cameraController.startRunning()
                    }
                }) {
                    Text(cameraController.isCameraRunning ? "Stop" : "Start")
                        .foregroundColor(.white)
                        .padding()
                        .background(cameraController.isCameraRunning ? Color.red : Color.blue)
                        .cornerRadius(10)
                }
                Button("サーバー URL を設定") {
                    showingSheet = true
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                
                Button(action: {
                    guard let scannedBooks = cameraController.scannedBooks else { return }
                    if scannedBooks.isbns.isEmpty {
                        alertMessage = "空の配列は送信できません。"
                        showingAlert = true
                    } else {
                        NetworkManager.shared.postIsbns(isbns: scannedBooks.isbns) { saved, failed, errorMessage in
                            if let errorMessage = errorMessage {
                                alertMessage = errorMessage
                            } else if failed.isEmpty {
                                alertMessage = "すべてのISBNが正常に送信されました。"
                                scannedBooks.isbns.removeAll()
                            } else {
                                alertMessage = "以下のISBNの保存に失敗しました:\n" + failed.joined(separator: "\n")
                                scannedBooks.isbns.removeAll()
                            }
                            
                            showingAlert = true
                        }
                    }
                }) {
                    Text("送信")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(10)
                }
            }
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("送信結果"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }.onAppear {
            if let currentIndex = serverURLs.firstIndex(of: UserDefaults.standard.string(forKey: "currentServerURL") ?? "") {
                selectedURLIndex = currentIndex
            }
        }.sheet(isPresented: $showingSheet) {
            ServerURLInputView(serverURLs: $serverURLs, selectedURLIndex: $selectedURLIndex)
        }
    }
}
struct ServerURLInputView: View {
    @Binding var serverURLs: [String]
    @Binding var selectedURLIndex: Int
    @State private var newURL = ""
    @State private var editingURLIndex: Int? = nil // 編集中のURLのインデックスを追跡
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("新しいサーバー URL を追加")) {
                    TextField("新しいサーバー URL を入力", text: $newURL)
                    Button("追加") {
                        addNewURL()
                    }
                }

                Section(header: Text("保存されたURL")) {
                    List {
                        ForEach(serverURLs.indices, id: \.self) { index in
                            if editingURLIndex == index {
                                TextField("URLを編集", text: $serverURLs[index], onCommit: {
                                    updateURLs()
                                })
                                .id(index) // ビューが更新されるたびに再レンダリング
                            } else {
                                Text(serverURLs[index])
                                    .onTapGesture {
                                        editingURLIndex = index // 編集モードを有効にする
                                    }
                            }
                        }
                        .onDelete(perform: deleteURLs)
                    }
                }
            }
            .navigationTitle("URL 設定")
            .navigationBarItems(trailing: Button("閉じる") {
                dismiss()
            })
        }
    }

    private func addNewURL() {
        guard !newURL.isEmpty, !serverURLs.contains(newURL) else { return }
        serverURLs.append(newURL)
        selectedURLIndex = serverURLs.count - 1
        updateURLs()
        newURL = "" // テキストフィールドをクリア
        dismiss()
    }

    private func updateURLs() {
        UserDefaults.standard.set(serverURLs, forKey: "serverURLs")
        if let index = editingURLIndex, serverURLs.indices.contains(index) {
            selectedURLIndex = index
            UserDefaults.standard.set(serverURLs[index], forKey: "currentServerURL")
        }
        editingURLIndex = nil // 編集モードを終了
    }

    private func deleteURLs(at offsets: IndexSet) {
        if let index = offsets.first, serverURLs[index] == UserDefaults.standard.string(forKey: "currentServerURL") {
            UserDefaults.standard.removeObject(forKey: "currentServerURL")
            selectedURLIndex = 0 // リストが空でなければ最初の要素を選択
        }
        serverURLs.remove(atOffsets: offsets)
        updateURLs()
    }
}


struct ISBNListView: View {
    @ObservedObject var scannedBooks: ScannedBooks
    var body: some View {
        List {
            ForEach(scannedBooks.isbns, id: \.self) { isbn in
                HStack {
                    Text(isbn)
                    Spacer()
                    Button(action: {
                        if let index = scannedBooks.isbns.firstIndex(of: isbn) {
                            scannedBooks.removeISBNs(at: IndexSet(integer: index))
                        }
                    }) {
                        Image(systemName: "trash") // ゴミ箱アイコンを使用
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    var previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if uiView.layer.sublayers == nil {
                uiView.layer.addSublayer(previewLayer)
            }
            previewLayer.frame = uiView.bounds
        }
    }
}

struct BarcodeOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // スキャンエリアの定義
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 200, height: 50)
                    .overlay(
                        Rectangle().stroke(Color.white, lineWidth: 2)
                    )
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
    }
}
