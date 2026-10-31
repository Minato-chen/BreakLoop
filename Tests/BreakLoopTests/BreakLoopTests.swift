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
            userDefaults: mockUserDefaults,
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
            userDefaults: mockUserDefaults,
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
            userDefaults: mockUserDefaults,
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
            userDefaults: mockUserDefaults,
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
            userDefaults: mockUserDefaults,
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
    
    // MARK: - 测试 7: 模块化流水线拼装循环与任意位置待机测试
    func testModularPipelineLoopAndJump() {
        // 自定义 4 模块：工作 20m -> 休息 5m(倒计时) -> 工作 30m -> 自由休息(正计时)
        let customBlocks = [
            FlowBlock.makeWork(name: "热身工作", minutes: 20),
            FlowBlock.makeCountdownRest(name: "固定休息", minutes: 5),
            FlowBlock.makeWork(name: "深度工作", minutes: 30),
            FlowBlock.makeStopwatchRest(name: "自由大休", targetSeconds: 300)
        ]
        
        let preset = Preset(
            name: "我的快捷指令混合流",
            blocks: customBlocks
        )
        
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            userDefaults: mockUserDefaults,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        
        XCTAssertEqual(engine.mode, .standby)
        XCTAssertEqual(engine.currentBlockIndex, 0)
        
        // 1. 启动第 1 步 (工作 20m)
        engine.startCurrentBlock()
        XCTAssertEqual(engine.mode, .working)
        XCTAssertEqual(engine.currentBlock?.name, "热身工作")
        XCTAssertEqual(engine.currentSeconds, 20 * 60)
        
        // 模拟第 1 步结束，推进到第 2 步 (休息 5m 倒计时)
        simulatedDate.addTimeInterval(20 * 60)
        engine.tick()
        XCTAssertEqual(engine.currentBlockIndex, 1)
        XCTAssertEqual(engine.mode, .resting)
        XCTAssertEqual(engine.currentBlock?.name, "固定休息")
        XCTAssertEqual(engine.currentBlock?.timingMode, .countdown)
        XCTAssertEqual(engine.currentSeconds, 5 * 60)
        
        // 2. 任意位置跳出待机测试（在第 2 步休息中挂起进入待机）
        engine.enterStandby(reason: .manual)
        XCTAssertEqual(engine.mode, .standby)
        // 验证待机后不会丢失当前模块定位
        XCTAssertEqual(engine.currentBlockIndex, 1)
        
        // 3. 从待机唤醒并跳转到第 3 步 (深度工作 30m)
        engine.jumpToBlock(index: 2)
        XCTAssertEqual(engine.currentBlockIndex, 2)
        XCTAssertEqual(engine.mode, .working)
        XCTAssertEqual(engine.currentBlock?.name, "深度工作")
        XCTAssertEqual(engine.currentSeconds, 30 * 60)
        
        // 模拟第 3 步结束，推进到第 4 步 (自由大休 正计时)
        simulatedDate.addTimeInterval(30 * 60)
        engine.tick()
        XCTAssertEqual(engine.currentBlockIndex, 3)
        XCTAssertEqual(engine.mode, .resting)
        XCTAssertEqual(engine.currentBlock?.name, "自由大休")
        XCTAssertEqual(engine.currentBlock?.timingMode, .stopwatch)
        
        // 4. 模拟第 4 步结束，测试回路闭环（循环回到第 0 步，大循环轮次 +1）
        XCTAssertEqual(engine.completedCycles, 0)
        engine.advanceToNextBlock()
        XCTAssertEqual(engine.currentBlockIndex, 0)
        XCTAssertEqual(engine.completedCycles, 1)
        XCTAssertEqual(engine.mode, .working)
        XCTAssertEqual(engine.currentBlock?.name, "热身工作")
    }
    
    // MARK: - 测试 8: 模块向上插入与至少保留一个模块守卫
    func testBlockInsertionAndSingleBlockGuard() {
        var preset = Preset(
            name: "单模块测试",
            blocks: [
                FlowBlock.makeWork(name: "初始工作", minutes: 25)
            ]
        )
        
        // 向上方插入休息模块（插入到 index 0）
        let topBlock = FlowBlock.makeCountdownRest(name: "开头休息", minutes: 5)
        preset.blocks.insert(topBlock, at: 0)
        XCTAssertEqual(preset.blocks.count, 2)
        XCTAssertEqual(preset.blocks[0].name, "开头休息")
        XCTAssertEqual(preset.blocks[1].name, "初始工作")
        
        // 向下方追加模块（插入到末尾）
        let bottomBlock = FlowBlock.makeWork(name: "末尾工作", minutes: 15)
        preset.blocks.append(bottomBlock)
        XCTAssertEqual(preset.blocks.count, 3)
        XCTAssertEqual(preset.blocks[2].name, "末尾工作")
        
        // 测试至少保留 1 个模块守卫规则
        func deleteBlock(from p: inout Preset, at index: Int) -> Bool {
            guard p.blocks.count > 1 else { return false }
            p.blocks.remove(at: index)
            return true
        }
        
        // 连续删除两次（从 3 个删到 1 个）
        XCTAssertTrue(deleteBlock(from: &preset, at: 0))
        XCTAssertEqual(preset.blocks.count, 2)
        XCTAssertTrue(deleteBlock(from: &preset, at: 0))
        XCTAssertEqual(preset.blocks.count, 1)
        
        // 最后 1 个模块时，删除应被拒绝拦截
        XCTAssertFalse(deleteBlock(from: &preset, at: 0))
        XCTAssertEqual(preset.blocks.count, 1)
        XCTAssertEqual(preset.blocks[0].name, "末尾工作")
    }
    
    // MARK: - 测试 9: 菜单栏时间提示不出现 < 等特殊符号
    func testMenuBarTextAndNoLessThanSymbols() {
        // 1. 小于 1 分钟（如 20 秒、45 秒）显示纯净 1m，绝无 < 符号
        XCTAssertEqual(TimeFormatter.formatMinutesOnly(seconds: 20), "1m")
        XCTAssertEqual(TimeFormatter.formatMinutesOnly(seconds: 45), "1m")
        XCTAssertEqual(TimeFormatter.formatMinutesOnly(seconds: 0), "0m")
        XCTAssertEqual(TimeFormatter.formatMinutesOnly(seconds: 60), "1m")
        XCTAssertEqual(TimeFormatter.formatMinutesOnly(seconds: 90), "2m")
        
        // 2. 引擎菜单栏文本：无 + 或 < 等冗余符号
        let preset = Preset(
            name: "格式测试",
            blocks: [
                FlowBlock.makeWork(name: "专注", minutes: 25),
                FlowBlock.makeStopwatchRest(name: "正计息", targetSeconds: 20)
            ]
        )
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            userDefaults: mockUserDefaults,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        
        // 待机状态
        XCTAssertFalse(engine.menuBarText.contains("<"))
        XCTAssertFalse(engine.menuBarText.contains("+"))
        
        // 工作状态
        engine.startCurrentBlock()
        XCTAssertFalse(engine.menuBarText.contains("<"))
        XCTAssertFalse(engine.menuBarText.contains("+"))
        
        // 推进到自由正计时休息
        engine.advanceToNextBlock()
        simulatedDate.addTimeInterval(45)
        engine.tick()
        XCTAssertFalse(engine.menuBarText.contains("<"))
        XCTAssertFalse(engine.menuBarText.contains("+"))
    }
    
    // MARK: - 测试 10: 工作模块强制倒计时与固定属性守卫
    func testWorkModuleStrictCountdownRule() {
        let work = FlowBlock.makeWork(name: "专注", minutes: 30)
        XCTAssertEqual(work.type, .work)
        XCTAssertEqual(work.timingMode, .countdown)
        
        // 尝试初始化为工作 + 正计时，应被守卫强制修正为倒计时
        let coercedWork = FlowBlock(type: .work, name: "专注测试", durationMinutes: 25, timingMode: .stopwatch)
        XCTAssertEqual(coercedWork.type, .work)
        XCTAssertEqual(coercedWork.timingMode, .countdown)
        
        // 休息模块则完全支持倒计时与正计时双重模式
        let cdRest = FlowBlock.makeCountdownRest(name: "短休", minutes: 5)
        XCTAssertEqual(cdRest.type, .rest)
        XCTAssertEqual(cdRest.timingMode, .countdown)
        
        let swRest = FlowBlock.makeStopwatchRest(name: "看远方", targetSeconds: 20)
        XCTAssertEqual(swRest.type, .rest)
        XCTAssertEqual(swRest.timingMode, .stopwatch)
    }
    
    // MARK: - 测试 11: 声音中心默认重复3次、长音保护与系统音预设
    func testSoundManagerDefaultsAndCustomSounds() {
        let soundManager = SoundManager.shared
        // 默认 3 次重复
        XCTAssertEqual(soundManager.defaultRepeatCount, 3)
        // 默认截断时间处于 10~15 秒区间 (12.0)
        XCTAssertGreaterThanOrEqual(soundManager.maxDurationSeconds, 10.0)
        XCTAssertLessThanOrEqual(soundManager.maxDurationSeconds, 15.0)
        
        // 内置系统声音库存在且不少于 5 种常用声音
        let allSounds = soundManager.allAvailableSounds()
        XCTAssertGreaterThanOrEqual(allSounds.count, 5)
        XCTAssertTrue(allSounds.contains(where: { $0.identifier == "Glass" }))
        XCTAssertTrue(allSounds.contains(where: { $0.identifier == "Ping" }))
        
        // 全局默认提醒文案初始值与 FlowBlock 自动采用
        XCTAssertFalse(soundManager.defaultWorkMessage.isEmpty)
        XCTAssertFalse(soundManager.defaultRestMessage.isEmpty)
        
        let newWorkBlock = FlowBlock.makeWork()
        XCTAssertEqual(newWorkBlock.message, soundManager.defaultWorkMessage)
        XCTAssertEqual(newWorkBlock.soundName, soundManager.defaultWorkSound)
        
        let newRestBlock = FlowBlock.makeCountdownRest()
        XCTAssertEqual(newRestBlock.message, soundManager.defaultRestMessage)
        XCTAssertEqual(newRestBlock.soundName, soundManager.defaultRestSound)
    }
    
    // MARK: - 测试 12: 暂停与继续计时控制
    func testPauseAndResume() {
        let preset = Preset(
            name: "PauseTest",
            blocks: [
                FlowBlock.makeWork(name: "专注", minutes: 20),
                FlowBlock.makeCountdownRest(name: "休息", minutes: 5)
            ]
        )
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            userDefaults: mockUserDefaults,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        engine.startCurrentBlock()
        XCTAssertEqual(engine.mode, .working)
        XCTAssertFalse(engine.isPaused)
        
        // 前进 60 秒
        simulatedDate.addTimeInterval(60)
        engine.tick()
        let secondsBeforePause = engine.currentSeconds
        
        // 触发暂停
        engine.pause()
        XCTAssertTrue(engine.isPaused)
        XCTAssertTrue(engine.menuBarText.contains("暂停中"))
        
        // 暂停期间时间流逝 120 秒，tick 不应该扣除当前倒计时
        simulatedDate.addTimeInterval(120)
        engine.tick()
        XCTAssertEqual(engine.currentSeconds, secondsBeforePause)
        
        // 恢复计时
        engine.resume()
        XCTAssertFalse(engine.isPaused)
        XCTAssertEqual(engine.currentSeconds, secondsBeforePause)
        
        // 恢复后正常走时 30 秒
        simulatedDate.addTimeInterval(30)
        engine.tick()
        XCTAssertEqual(engine.currentSeconds, secondsBeforePause - 30)
    }
    
    // MARK: - 测试 13: 暂停超时自动转待机并回溯
    func testPauseTimeoutAutoStandby() {
        mockUserDefaults.set(5, forKey: "BreakLoop.PauseTimeoutMinutes")
        let preset = Preset(
            name: "PauseTimeoutTest",
            blocks: [FlowBlock.makeWork(name: "专注", minutes: 25)]
        )
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            userDefaults: mockUserDefaults,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        engine.startCurrentBlock()
        engine.pause()
        XCTAssertTrue(engine.isPaused)
        
        // 暂停 6 分钟 (超过设定的 5 分钟上限)
        simulatedDate.addTimeInterval(6 * 60)
        engine.tick()
        
        // 引擎应自动收起进入待机态
        XCTAssertEqual(engine.mode, .standby)
        XCTAssertFalse(engine.isPaused)
    }
    
    // MARK: - 测试 14: 打断恢复策略 (重置本步 / 断点续传 / 重置整轮)
    func testInterruptionRecoveryStrategy() {
        let preset = Preset(
            name: "RecoveryTest",
            blocks: [
                FlowBlock.makeWork(name: "番茄 1", minutes: 20),
                FlowBlock.makeCountdownRest(name: "短休 1", minutes: 5),
                FlowBlock.makeWork(name: "番茄 2", minutes: 20)
            ],
            manualStandbyRecovery: .resume,
            passiveStandbyRecovery: .resetCurrent
        )
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            userDefaults: mockUserDefaults,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        engine.startCurrentBlock()
        
        // 运行 5 分钟 (剩余 15 分钟 = 900 秒)
        simulatedDate.addTimeInterval(5 * 60)
        engine.tick()
        XCTAssertEqual(engine.currentSeconds, 15 * 60)
        
        // 手动待机 (策略: .resume 断点续传)
        engine.enterStandby(reason: .manual)
        XCTAssertEqual(engine.mode, .standby)
        
        // 重新启动：由于策略为 .resume，应当保留还剩 15 分钟继续倒数
        engine.startCurrentBlock()
        XCTAssertEqual(engine.mode, .working)
        XCTAssertEqual(engine.currentSeconds, 15 * 60)
        
        // 再次被动待机（如锁屏 .locked，策略: .resetCurrent 重置当前步）
        engine.enterStandby(reason: .locked)
        engine.startCurrentBlock()
        // 应当重新计满 20 分钟
        XCTAssertEqual(engine.currentSeconds, 20 * 60)
    }
}
