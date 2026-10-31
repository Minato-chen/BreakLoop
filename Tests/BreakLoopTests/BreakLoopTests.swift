import XCTest
@testable import BreakLoop

final class BreakLoopTests: XCTestCase {
    var tempDirectory: URL!
    var sessionStore: SessionStore!
    var mockUserDefaults: UserDefaults!
    var simulatedDate: Date!
    
    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        let suiteName = "com.breakloop.tests.\(UUID().uuidString)"
        mockUserDefaults = UserDefaults(suiteName: suiteName)!
        sessionStore = SessionStore(baseDirectory: tempDirectory, userDefaults: mockUserDefaults)
        
        simulatedDate = Date(timeIntervalSince1970: 1700000000)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    // MARK: - 测试 1: Working -> Resting -> Working 循环
    func testWorkingToRestingCycle() {
        let preset = Preset(
            name: "TestPreset",
            mode: .continuousLoop,
            workMinutes: 20,
            autoStartRest: true,
            restTimingMode: .stopwatch,
            restTargetSeconds: 20,
            restMinutes: 1
        )
        
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        
        XCTAssertEqual(engine.mode, .standby)
        
        // 开始工作
        engine.startWork()
        XCTAssertEqual(engine.mode, .working)
        XCTAssertEqual(engine.currentSeconds, 20 * 60)
        
        // 推进时间 20 分钟
        simulatedDate.addTimeInterval(20 * 60)
        engine.tick()
        
        // 验证自动进入休息（因为 autoStartRest == true）
        XCTAssertEqual(engine.mode, .resting)
        XCTAssertEqual(engine.currentSeconds, 0) // stopwatch 模式从 0 开始
        
        // 推进休息 30 秒
        simulatedDate.addTimeInterval(30)
        engine.tick()
        XCTAssertEqual(engine.currentSeconds, 30)
        
        // 点击开始下一轮工作
        engine.startNextWorkCycle()
        XCTAssertEqual(engine.mode, .working)
        XCTAssertEqual(engine.completedCycles, 1)
        
        // 验证存储了两个 session: 1个 work, 1个 rest
        let allSessions = sessionStore.sessions(in: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 2000000000))
        XCTAssertEqual(allSessions.count, 2)
        XCTAssertEqual(allSessions[0].kind, .work)
        XCTAssertEqual(allSessions[0].endReason, .completed)
        XCTAssertEqual(allSessions[1].kind, .rest)
    }
    
    // MARK: - 测试 2: 任意状态手动待机与空闲时间回溯
    func testEnterStandbyWithBacktracking() {
        let preset = Preset(
            name: "TestPreset",
            workMinutes: 25,
            idleMinutes: 10
        )
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        
        engine.startWork()
        
        // 推进 15 分钟，此时发生最后一次键盘输入
        simulatedDate.addTimeInterval(15 * 60)
        let lastActivityDate = simulatedDate!
        
        // 推进到第 25 分钟，空闲检测触发（已经静置 10 分钟）
        simulatedDate.addTimeInterval(10 * 60)
        
        // 进入待机，结束时间回溯到最后活跃时间
        engine.enterStandby(reason: .idle, at: lastActivityDate)
        
        XCTAssertEqual(engine.mode, .standby)
        
        let allSessions = sessionStore.sessions(in: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 2000000000))
        XCTAssertEqual(allSessions.count, 1)
        let savedSession = allSessions[0]
        XCTAssertEqual(savedSession.endReason, .idle)
        XCTAssertEqual(savedSession.duration, 15 * 60, accuracy: 1.0) // 记录的是 15 分钟，而不是 25 分钟
    }
    
    // MARK: - 测试 3: 极简状态流转
    func testSimpleModeTransition() {
        let preset = Preset(name: "TestPreset", workMinutes: 10)
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        
        engine.startWork()
        XCTAssertEqual(engine.mode, .working)
        
        // 点击进入休息
        engine.startRest()
        XCTAssertEqual(engine.mode, .resting)
        
        // 点击开始工作
        engine.startNextWorkCycle()
        XCTAssertEqual(engine.mode, .working)
        XCTAssertEqual(engine.completedCycles, 1)
    }
    
    // MARK: - 测试 4: 休息超上限自动待机 (.restTimeout)
    func testRestTimeoutAutoStandby() {
        let preset = Preset(name: "TestPreset", restMaxMinutes: 30)
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        
        engine.startRest()
        XCTAssertEqual(engine.mode, .resting)
        
        // 推进 30 分钟整
        simulatedDate.addTimeInterval(30 * 60)
        engine.tick()
        
        // 应当自动进入 standby，且 reason 为 .restTimeout
        XCTAssertEqual(engine.mode, .standby)
        
        let sessions = sessionStore.sessions(in: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 2000000000))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].kind, .rest)
        XCTAssertEqual(sessions[0].endReason, .restTimeout)
    }
    
    // MARK: - 测试 5: 崩溃恢复补记
    func testCrashRecovery() {
        let startDate = simulatedDate!
        let ongoingSession = Session(
            kind: .work,
            start: startDate,
            end: startDate.addingTimeInterval(300),
            presetName: "CrashTest",
            endReason: .manual
        )
        
        // 模拟崩溃前记录的心跳
        let heartbeatTime = startDate.addingTimeInterval(600) // 10分钟后心跳
        sessionStore.recordHeartbeat(session: ongoingSession, at: heartbeatTime)
        
        // 新建 store，模拟重启应用恢复
        let recoveredStore = SessionStore(baseDirectory: tempDirectory, userDefaults: mockUserDefaults)
        let recoveredSession = recoveredStore.recoverUnfinishedSessionIfNeeded()
        
        XCTAssertNotNil(recoveredSession)
        XCTAssertEqual(recoveredSession?.endReason, .crashed)
        if let duration = recoveredSession?.duration {
            XCTAssertEqual(duration, 600, accuracy: 1.0)
        } else {
            XCTFail("Recovered session duration should not be nil")
        }
    }
    
    // MARK: - 测试 6: 轮换提醒触发
    func testRotationAlertRule() {
        let preset = Preset(
            name: "RotationTest",
            workMinutes: 20,
            autoStartRest: true,
            message: "看远方",
            rotation: [
                RotationRule(everyNthCycle: 2, message: "喝水"),
                RotationRule(everyNthCycle: 3, message: "站立活动")
            ]
        )
        
        var receivedAlerts: [AlertTriggerEvent] = []
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        engine.onAlertTriggered = { event in
            receivedAlerts.append(event)
        }
        
        // 第 1 轮
        engine.startWork()
        simulatedDate.addTimeInterval(20 * 60)
        engine.tick()
        XCTAssertEqual(receivedAlerts.last?.message, "看远方")
        
        // 第 2 轮
        engine.startNextWorkCycle()
        simulatedDate.addTimeInterval(20 * 60)
        engine.tick()
        XCTAssertEqual(receivedAlerts.last?.message, "喝水")
        
        // 第 3 轮
        engine.startNextWorkCycle()
        simulatedDate.addTimeInterval(20 * 60)
        engine.tick()
        XCTAssertEqual(receivedAlerts.last?.message, "站立活动")
    }
}
