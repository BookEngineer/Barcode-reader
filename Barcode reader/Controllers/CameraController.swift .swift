import AVFoundation
import UIKit
import Combine

class CameraController: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    private var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var scannedBooks: ScannedBooks?
    @Published var isCameraRunning = false
    @Published var errorMessage: String?
    @Published var lastScannedCode: String?
    

    override init() {
        super.init()
        self.scannedBooks = ScannedBooks()
        setupCaptureSession()
    }

    func setupCaptureSession() {
        let session = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            errorMessage = "カメラが利用できません。"
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            guard session.canAddInput(videoInput) else {
                errorMessage = "ビデオ入力を追加できません。"
                return
            }
            session.addInput(videoInput)

            let metadataOutput = AVCaptureMetadataOutput()
            guard session.canAddOutput(metadataOutput) else {
                errorMessage = "メタデータ出力を追加できません。"
                return
            }
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean13] // EAN-13バーコードのみ読み取る

            // プレビューレイヤーと読み取り範囲の設定
            previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer?.videoGravity = .resizeAspectFill
            captureSession = session

            // rectOfInterest の設定
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { // レイアウトが確定した後に実行
                if let previewLayer = self.previewLayer {
                    let width = previewLayer.bounds.width
                    let height = previewLayer.bounds.height
                    
                    // スキャン範囲をプレビューの中心に設定（300px幅、100px高さ）
                    let scanWidth: CGFloat = 200
                    let scanHeight: CGFloat = 25
                    let posX = (width - scanWidth) / 2
                    let posY = (height - scanHeight) / 2

                    let normalizedX = posX / width
                    let normalizedY = posY / height
                    let normalizedWidth = scanWidth / width
                    let normalizedHeight = scanHeight / height
                    
                    // AVCaptureVideoPreviewLayer の座標系で X と Y は逆になることに注意
                    metadataOutput.rectOfInterest = CGRect(x: normalizedY, y: normalizedX, width: normalizedHeight, height: normalizedWidth)
                }
            }
        } catch {
            errorMessage = "カメラ設定中にエラーが発生しました: \(error.localizedDescription)"
        }
    }
    func startRunning() {
        guard let session = captureSession, !session.isRunning else {
            return
        }
        session.startRunning()
        isCameraRunning = true
    }

    func stopRunning() {
        guard let session = captureSession, session.isRunning else {
            return
        }
        session.stopRunning()
        isCameraRunning = false
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let code = metadataObject.stringValue {
            
            // ISBN-13バリデーションを実行
            if isValidISBN13(code) {
                DispatchQueue.main.async {
                    self.scannedBooks?.addISBN(code) // ScannedBooksの配列にISBNを追加
                }
            }
        }
    }

    func isValidISBN13(_ code: String) -> Bool {
        let digits = code.filter { "0"..."9" ~= $0 }
        
        // プレフィックスが978または979であり、全ての文字が数字であることを確認
        if digits.count == 13 && (code.hasPrefix("978") || code.hasPrefix("979")) {
            return validateISBN13(digits)
        }
        return false
    }

    func validateISBN13(_ isbn: String) -> Bool {
        let digits = isbn.compactMap { Int(String($0)) }
        guard digits.count == 13 else { return false }
        
        let sum = digits.enumerated().reduce(0) {
            $0 + ($1.offset % 2 == 0 ? $1.element : $1.element * 3)
        }
        return (sum % 10 == 0)
    }

}

class ScannedBooks: ObservableObject {
    @Published var isbns: [String] = [] {
        didSet {
            print("Updated ISBNs: \(isbns)")
        }
    }
    
    func addISBN(_ isbn: String) {
        if !isbns.contains(isbn) { // ISBNがリストにまだ存在していない場合のみ追加
            isbns.append(isbn)
            // ハプティックフィードバックを発生させる
            let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
            feedbackGenerator.prepare()
            feedbackGenerator.impactOccurred()
        }
    }
    
    func removeISBNs(at offsets: IndexSet) {
        isbns.remove(atOffsets: offsets)
    }
}
