import Foundation

public final class SessionStore {
    public let baseDirectory: URL
    private let userDefaults: UserDefaults
    private let queue = DispatchQueue(label: "com.breakloop.sessionstore", qos: .utility)
    
    // 心跳与恢复的 UserDefaults 键
    private let heartbeatTimestampKey = "BreakLoop.Heartbeat.timestamp"
    private let activeSessionKey = "BreakLoop.Heartbeat.activeSession"
    
    // 内存轻量级缓存，杜绝重复从磁盘加载与 JSON 反序列化（大幅压低内存开销）
    private var memoryCache: [String: [Session]] = [:]
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df
    }()
    
    private let isoDateFormatter: ISO8601DateFormatter = {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return df
    }()
    
    public init(
        baseDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        if let dir = baseDirectory {
            self.baseDirectory = dir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseDirectory = appSupport.appendingPathComponent("BreakLoop", isDirectory: true)
        }
        self.userDefaults = userDefaults
        try? FileManager.default.createDirectory(at: self.baseDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - 文件命名规则 (按月)
    private func fileURL(for date: Date) -> URL {
        let monthString = dateFormatter.string(from: date)
        return baseDirectory.appendingPathComponent("sessions-\(monthString).json")
    }
    
    // MARK: - 写入 Session (原子写入)
    @discardableResult
    public func append(_ session: Session) -> Bool {
        // 规则：小于 3 秒的无意义段丢弃
        guard session.duration >= 3.0 else {
            return false
        }
        
        return queue.sync {
            let monthKey = dateFormatter.string(from: session.start)
            let url = fileURL(for: session.start)
            var currentSessions = loadSessionsSync(from: url, monthKey: monthKey)
            currentSessions.append(session)
            return saveSessionsSync(currentSessions, to: url, monthKey: monthKey)
        }
    }
    
    // MARK: - 查询指定范围内的 Sessions
    public func sessions(in range: ClosedRange<Date>) -> [Session] {
        return queue.sync {
            var result: [Session] = []
            var current = range.lowerBound
            var visitedMonths = Set<String>()
            
            let calendar = Calendar.current
            while current <= range.upperBound {
                let monthStr = dateFormatter.string(from: current)
                if !visitedMonths.contains(monthStr) {
                    visitedMonths.insert(monthStr)
                    let url = fileURL(for: current)
                    let list = loadSessionsSync(from: url, monthKey: monthStr)
                    result.append(contentsOf: list)
                }
                guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
                current = next
            }
            
            // 过滤并排序
            return result
                .filter { $0.start <= range.upperBound && $0.end >= range.lowerBound }
                .sorted { $0.start < $1.start }
        }
    }
    
    // MARK: - 导出 CSV
    public func exportCSV(for range: ClosedRange<Date>) -> String {
        let list = sessions(in: range)
        var csv = "ID,Kind,Start,End,DurationSeconds,PresetName,EndReason\n"
        for s in list {
            let line = "\(s.id.uuidString),\(s.kind.rawValue),\(isoDateFormatter.string(from: s.start)),\(isoDateFormatter.string(from: s.end)),\(Int(s.duration)),\"\(s.presetName)\",\(s.endReason.rawValue)\n"
            csv.append(line)
        }
        return csv
    }
    
    // MARK: - 心跳与崩溃恢复
    
    /// 记录当前正在进行的会话心跳
    public func recordHeartbeat(session: Session, at time: Date = Date()) {
        userDefaults.set(time.timeIntervalSince1970, forKey: heartbeatTimestampKey)
        if let data = try? JSONEncoder().encode(session) {
            userDefaults.set(data, forKey: activeSessionKey)
        }
    }
    
    /// 轻量更新心跳时间戳（无需任何 JSON 编解码）
    public func updateHeartbeatTimestamp(at time: Date = Date()) {
        userDefaults.set(time.timeIntervalSince1970, forKey: heartbeatTimestampKey)
    }
    
    /// 清除活跃心跳（正常进入待机或正常结束时调用）
    public func clearHeartbeat() {
        userDefaults.removeObject(forKey: heartbeatTimestampKey)
        userDefaults.removeObject(forKey: activeSessionKey)
    }
    
    /// 检查并恢复可能崩溃的未关闭会话
    @discardableResult
    public func recoverUnfinishedSessionIfNeeded() -> Session? {
        guard let data = userDefaults.data(forKey: activeSessionKey),
              var session = try? JSONDecoder().decode(Session.self, from: data) else {
            clearHeartbeat()
            return nil
        }
        
        let lastHeartbeatTimestamp = userDefaults.double(forKey: heartbeatTimestampKey)
        let lastTime = lastHeartbeatTimestamp > 0 ? Date(timeIntervalSince1970: lastHeartbeatTimestamp) : session.start
        
        // 修正结束时间和原因
        session.end = max(session.start, lastTime)
        session.endReason = .crashed
        
        clearHeartbeat()
        
        if append(session) {
            return session
        }
        return nil
    }
    
    // MARK: - 私有辅助 (同步调用，需在 queue 内)
    private func loadSessionsSync(from url: URL, monthKey: String) -> [Session] {
        if let cached = memoryCache[monthKey] {
            return cached
        }
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let sessions = try? JSONDecoder().decode([Session].self, from: data) else {
            memoryCache[monthKey] = []
            return []
        }
        memoryCache[monthKey] = sessions
        return sessions
    }
    
    private func saveSessionsSync(_ sessions: [Session], to url: URL, monthKey: String) -> Bool {
        memoryCache[monthKey] = sessions
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
