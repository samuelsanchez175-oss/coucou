import CommonCrypto
import Darwin
import Foundation

/// Reads what is left of Claude, Grok, ChatGPT, Antigravity, and Grok Bot. A miss stays blank.
@MainActor
final class UsageMonitor: ObservableObject {
    static let shared = UsageMonitor()

    @Published private(set) var readings: [UsageService: UsageLevels] = [:]
    private var timer: Timer?
    private var inFlight: Set<UsageService> = []

    func levels(_ service: UsageService) -> UsageLevels {
        readings[service] ?? UsageLevels()
    }

    func start() {
        guard timer == nil else { return }
        readings = UsageLimitStore.load()
        if readings[.claude]?.hasReading != true, let history = UsageFetcher.claudeHistory() {
            readings[.claude] = history
            UsageLimitStore.save(readings)
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            Task { @MainActor in UsageMonitor.shared.refresh() }
        }
    }

    /// The button under the arrow. It saves a fresh reading, then asks Grok to force the rest.
    func forceRefresh() {
        inFlight.removeAll()
        refresh()
        submitGrokRefresh()
    }

    /// Each service lands on its own. A miss keeps the saved limits and their clock.
    func refresh() {
        for service in UsageBehavior.services where !inFlight.contains(service) {
            inFlight.insert(service)
            let saved = readings[service]
            Task.detached {
                let value = await UsageFetcher.reading(service)
                await MainActor.run {
                    var next = UsageMonitor.shared.readings
                    let kept = UsageBehavior.kept(fresh: value, saved: saved ?? next[service])
                    if kept.hasReading { next[service] = kept }
                    UsageMonitor.shared.readings = next
                    UsageLimitStore.save(next)
                    UsageMonitor.shared.inFlight.remove(service)
                }
            }
        }
    }

    private func submitGrokRefresh() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let grok = home.appendingPathComponent(".grok").appendingPathComponent("bin").appendingPathComponent("grok")
        guard FileManager.default.fileExists(atPath: grok.path) else { return }
        let limits = UsageLimitStore.fileURL()
        let folder = limits?.deletingLastPathComponent().path ?? home.path
        let command = UsageBehavior.usageRefreshCommand(
            grok: grok.path,
            folder: folder,
            limitsPath: limits?.path ?? folder
        )
        let script = """
        on run argv
          set cmd to item 1 of argv
          tell application "Terminal"
            do script cmd
          end tell
          return "ok"
        end run
        """
        _ = OSAScript.run(script, args: [command])
    }
}

/// Last good limits for every coding agent. A failed read does not erase this file.
enum UsageLimitStore {
    static func load() -> [UsageService: UsageLevels] {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var readings: [UsageService: UsageLevels] = [:]
        for service in UsageBehavior.services {
            guard let box = root[service.rawValue] as? [String: Any],
                  let rows = box["gates"] as? [[String: Any]] else { continue }
            let gates = rows.compactMap(gate(from:))
            let levels = UsageLevels(gates: gates)
            if levels.hasReading { readings[service] = levels }
        }
        return readings
    }

    static func save(_ readings: [UsageService: UsageLevels]) {
        guard let url = fileURL() else { return }
        var root: [String: Any] = [:]
        for (service, levels) in readings where levels.hasReading {
            root[service.rawValue] = [
                "gates": levels.gates.map { gate -> [String: Any] in
                    var row: [String: Any] = [
                        "model": gate.model,
                        "window": gate.window,
                    ]
                    if let remaining = gate.remaining { row["remaining"] = remaining }
                    if let replenishes = gate.replenishes { row["replenishes"] = replenishes.timeIntervalSince1970 }
                    if let savedAt = gate.savedAt { row["savedAt"] = savedAt.timeIntervalSince1970 }
                    return row
                }
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func fileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Coucou", isDirectory: true)
            .appendingPathComponent("usage-limits.json")
    }

    private static func gate(from row: [String: Any]) -> UsageGate? {
        guard let model = row["model"] as? String, let window = row["window"] as? String else { return nil }
        return UsageGate(
            model: model,
            window: window,
            remaining: row["remaining"] as? Int,
            replenishes: date(row["replenishes"]),
            savedAt: date(row["savedAt"])
        )
    }

    private static func date(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }
}

/// Live remaining percents. Tokens stay in memory and are not refreshed here.
enum UsageFetcher {
    static func reading(_ service: UsageService) async -> UsageLevels? {
        switch service {
        case .claude: return await claude()
        case .grok: return await grok()
        case .chatgpt: return await chatGPT()
        case .antigravity: return await antigravity()
        case .grokbot: return await grokbot()
        }
    }

    static func claude() async -> UsageLevels? {
        guard let token = claudeToken() else { return nil }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.32", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let data = await body(for: request) {
            let levels = UsageBehavior.parseClaude(data, model: savedModel("claudeModel", fallback: "claude-sonnet-4-6"))
            if levels.hasReading { return levels }
        }
        return claudeHistory()
    }

    /// The plan history Claude Desktop already saved. Used when the live read is refused.
    static func claudeHistory() -> UsageLevels? {
        let url = home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let levels = UsageBehavior.parseClaudeHistory(data)
        return levels.hasReading ? levels : nil
    }

    static func grok() async -> UsageLevels? {
        guard let token = grokToken() else { return nil }
        var request = URLRequest(url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let data = await body(for: request) else { return nil }
        return UsageBehavior.parseGrok(data, model: savedModel("grokModel", fallback: "grok-4.7"))
    }

    static func grokbot() async -> UsageLevels? {
        guard let token = grokBotToken() else { return nil }
        async let status = dashboard("GetSandUsageStatus", token: token)
        async let period = dashboard("GetCurrentPeriodUsage", token: token)
        let statusData = await status
        let periodData = await period
        guard statusData != nil || periodData != nil else { return nil }
        return UsageBehavior.parseGrokbot(status: statusData ?? Data(), period: periodData ?? Data())
    }

    static func chatGPT() async -> UsageLevels? {
        if let token = chatToken(), let account = chatAccount() {
            var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-ID")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let data = await body(for: request) {
                let levels = UsageBehavior.parseChatGPT(data)
                if levels.hasReading { return levels }
            }
        }
        return chatSnapshot()
    }

    static func antigravity() async -> UsageLevels? {
        guard let endpoint = antigravityEndpoint() else { return nil }
        let session = URLSession(configuration: .ephemeral, delegate: LocalHostTrust(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        for port in endpoint.ports {
            guard let url = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.setValue(endpoint.csrf, forHTTPHeaderField: "x-codeium-csrf-token")
            guard let data = await body(for: request, session: session), data.first == UInt8(ascii: "{") else { continue }
            return UsageBehavior.parseAntigravity(data)
        }
        return nil
    }

    private static func savedModel(_ key: String, fallback: String) -> String {
        let saved = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = (saved?.isEmpty == false) ? saved! : fallback
        let title = UsageBehavior.displayModel(id)
        return title.isEmpty ? UsageBehavior.displayModel(fallback) : title
    }

    private static func dashboard(_ method: String, token: String) async -> Data? {
        guard let url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/\(method)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        return await body(for: request)
    }

    /// Grok Bot stores the sign-in with the system safe-storage key. The password never leaves this function.
    private static func grokBotToken() -> String? {
        let password = shell("/usr/bin/security", ["find-generic-password", "-s", "Grok Bot Safe Storage", "-a", "Grok Bot Key", "-w"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty,
              let root = fileJSON("Library/Application Support/Grok Bot/sand-secrets.json"),
              let wrapped = root["cursor-accounts"] as? String,
              let accounts = json(Data(wrapped.utf8)),
              let book = accounts["accounts"] as? [String: Any] else { return nil }
        for value in book.values {
            guard let record = value as? [String: Any],
                  let encoded = record["cursor-access-token"] as? String,
                  let token = decryptSafeStorage(encoded, password: password),
                  token.contains(".") else { continue }
            return token
        }
        return nil
    }

    /// Electron safe storage: base64, a "v10" prefix, then AES-128-CBC. The key is PBKDF2 of the keychain password.
    private static func decryptSafeStorage(_ encoded: String, password: String) -> String? {
        guard let blob = Data(base64Encoded: encoded), blob.count > 3 else { return nil }
        let prefix = blob.prefix(3)
        guard prefix.elementsEqual(Data("v10".utf8)) else { return nil }
        let cipher = [UInt8](blob.dropFirst(3))
        guard !cipher.isEmpty, cipher.count.isMultiple(of: kCCBlockSizeAES128) else { return nil }
        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let derived = password.withCString { bytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                bytes, strlen(bytes),
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                1003,
                &key, key.count
            )
        }
        guard derived == kCCSuccess else { return nil }
        var iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var output = [UInt8](repeating: 0, count: cipher.count + kCCBlockSizeAES128)
        var moved = 0
        let decrypted = CCCrypt(
            CCOperation(kCCDecrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionPKCS7Padding),
            key, key.count,
            &iv,
            cipher, cipher.count,
            &output, output.count,
            &moved
        )
        guard decrypted == kCCSuccess, moved > 0 else { return nil }
        return String(bytes: output.prefix(moved), encoding: .utf8)
    }

    private static func body(for request: URLRequest, session: URLSession = .shared) async -> Data? {
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { return nil }
        return data
    }

    private static func claudeToken() -> String? {
        let raw = shell("/usr/bin/security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
        guard let data = raw.data(using: .utf8),
              let root = json(data),
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else { return nil }
        return token
    }

    private static func grokToken() -> String? {
        guard let root = fileJSON(".grok/auth.json") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for value in root.values {
            guard let entry = value as? [String: Any],
                  let token = entry["key"] as? String,
                  !token.isEmpty else { continue }
            if let stamp = entry["expires_at"] as? String, let expiry = formatter.date(from: stamp), expiry < Date() {
                continue
            }
            return token
        }
        return nil
    }

    private static func chatToken() -> String? {
        guard let tokens = fileJSON(".codex/auth.json")?["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              !token.isEmpty else { return nil }
        return token
    }

    private static func chatAccount() -> String? {
        guard let tokens = fileJSON(".codex/auth.json")?["tokens"] as? [String: Any],
              let account = tokens["account_id"] as? String,
              !account.isEmpty else { return nil }
        return account
    }

    /// Last rate-limit line Codex wrote, used when the live reading is unavailable.
    private static func chatSnapshot() -> UsageLevels? {
        guard let url = newestSession(),
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 400_000
        if end > window { try? handle.seek(toOffset: end - window) }
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n").reversed() where line.contains("used_percent") {
            let levels = UsageBehavior.parseChatGPT(Data(line.utf8))
            if levels.hasReading { return levels }
        }
        return nil
    }

    private static func newestSession() -> URL? {
        let root = home.appendingPathComponent(".codex/sessions")
        let fm = FileManager.default
        guard let years = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        for year in years.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            guard let months = try? fm.contentsOfDirectory(at: year, includingPropertiesForKeys: nil) else { continue }
            for month in months.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                guard let days = try? fm.contentsOfDirectory(at: month, includingPropertiesForKeys: nil) else { continue }
                for day in days.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                    let files = (try? fm.contentsOfDirectory(at: day, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                    let logs = files.filter { $0.pathExtension == "jsonl" }
                    if let newest = logs.max(by: { modified($0) < modified($1) }) { return newest }
                }
            }
        }
        return nil
    }

    /// A full `ps` listing can sit forever, so only the language server's own arguments are read.
    private static func antigravityEndpoint() -> (ports: [Int], csrf: String)? {
        for pid in processIDs() {
            guard pidPath(pid).contains("language_server") else { continue }
            let args = arguments(of: pid)
            guard let flag = args.firstIndex(of: "--csrf_token"), flag + 1 < args.count else { continue }
            let ports = listenPorts(pid: Int(pid))
            if !ports.isEmpty { return (ports, args[flag + 1]) }
        }
        return nil
    }

    private static func processIDs() -> [pid_t] {
        let capacity = 8192
        var pids = [pid_t](repeating: 0, count: capacity)
        // The return is how many ids were written, not a byte count.
        let written = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        let count = min(capacity, max(0, Int(written)))
        return Array(pids.prefix(count)).filter { $0 > 0 }
    }

    private static func pidPath(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "" }
        return String(cString: buffer)
    }

    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return [] }
        var data = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &data, &size, nil, 0) == 0, size > 4 else { return [] }
        let argc = data.prefix(4).withUnsafeBytes { raw -> Int32 in
            var value: Int32 = 0
            withUnsafeMutableBytes(of: &value) { dst in dst.copyBytes(from: raw) }
            return value
        }
        guard argc > 0 else { return [] }
        var offset = 4
        while offset < size, data[offset] != 0 { offset += 1 }
        while offset < size, data[offset] == 0 { offset += 1 }
        var args: [String] = []
        while offset < size, args.count < argc {
            let start = offset
            while offset < size, data[offset] != 0 { offset += 1 }
            if offset > start, let text = String(bytes: data[start..<offset], encoding: .utf8) {
                args.append(text)
            }
            offset += 1
        }
        return args
    }

    private static func listenPorts(pid: Int) -> [Int] {
        let listing = shell("/usr/sbin/lsof", ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN"], timeout: 3)
        var ports: [Int] = []
        for line in listing.split(separator: "\n") {
            guard let range = line.range(of: #"127\.0\.0\.1:\d+"#, options: .regularExpression) else { continue }
            let port = line[range].split(separator: ":").last.flatMap { Int($0) }
            if let port { ports.append(port) }
        }
        return ports
    }

    private static func fileJSON(_ relative: String) -> [String: Any]? {
        let url = home.appendingPathComponent(relative)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return json(data)
    }

    private static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func shell(_ launch: String, _ args: [String], timeout: TimeInterval? = nil) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch)
        process.arguments = args
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        if let timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                return ""
            }
        } else {
            process.waitUntilExit()
        }
        guard process.terminationStatus == 0 else { return "" }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

/// The Antigravity language server speaks HTTPS on localhost with its own certificate.
private final class LocalHostTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let host = challenge.protectionSpace.host
        guard host == "127.0.0.1" || host == "localhost",
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
