import Foundation

class NetworkManager {
    static let shared = NetworkManager()

    func postIsbns(isbns: [String], completion: @escaping ([String], [String], String?) -> Void) {
        guard let urlString = UserDefaults.standard.string(forKey: "currentServerURL"),
              let url = URL(string: urlString) else {
            completion([], [], "サーバー URL が無効です。")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ["isbn": isbns]
        do {
            print(payload)
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion([], [], "JSON エンコードに失敗しました。")
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error as? URLError, error.code == .timedOut {
                DispatchQueue.main.async {
                    completion([], [], "サーバーに接続できません。タイムアウトしました。")
                }
                return
            }
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completion([], [], error?.localizedDescription ?? "不明なエラーが発生しました。")
                }
                return
            }

            do {
                let jsonResponse = try JSONDecoder().decode(IsbnResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(jsonResponse.savedIsbns, jsonResponse.failedIsbns, nil)
                }
            } catch {
                DispatchQueue.main.async {
                    completion([], [], "JSON デコードエラー: \(error)")
                }
            }
        }
        task.resume()
    }
}

struct IsbnResponse: Codable {
    let message: String
    let savedIsbns: [String]
    let failedIsbns: [String]
}
