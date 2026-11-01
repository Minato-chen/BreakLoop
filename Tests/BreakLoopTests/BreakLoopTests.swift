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
        
        // 2. 任意位置跳出待机测试（在第 2 步休息中挂起进入待机，默认推进至下一步专注）
        engine.enterStandby(reason: .manual)
        XCTAssertEqual(engine.mode, .standby)
        XCTAssertEqual(engine.currentBlockIndex, 2)
        XCTAssertEqual(engine.currentBlock?.name, "深度工作")
        
        // 3. 从待机启动第 3 步 (深度工作 30m)
        engine.startCurrentBlock()
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
        
        // 2. 引擎菜单栏文本：符号与步数定制验证
        let preset = Preset(
            name: "格式测试",
            blocks: [
                FlowBlock.makeWork(name: "专注", minutes: 25),
                FlowBlock.makeStopwatchRest(name: "正计息")
            ]
        )
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            userDefaults: mockUserDefaults,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        
        // 待机状态默认：待命 (隐藏步数)
        XCTAssertEqual(engine.menuBarText, "待命")
        
        // 工作状态默认：< 25m (隐藏步数，倒计时带 <)
        engine.startCurrentBlock()
        XCTAssertEqual(engine.menuBarText, "< 25m")
        
        // 推进到自由正计时休息
        engine.advanceToNextBlock()
        simulatedDate.addTimeInterval(65)
        engine.tick()
        XCTAssertEqual(engine.menuBarText, "> 1m")
        
        // 开启显示步数
        mockUserDefaults.set(true, forKey: "BreakLoop.MenuBarShowStep")
        engine.updateMenuBarText()
        XCTAssertEqual(engine.menuBarText, "2/2 > 1m")
        
        // 关闭显示符号
        mockUserDefaults.set(false, forKey: "BreakLoop.MenuBarShowSymbol")
        engine.updateMenuBarText()
        XCTAssertEqual(engine.menuBarText, "2/2 1m")
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
        
        // 验证全局静音开关与试听强制发声
        soundManager.isMuted = true
        XCTAssertTrue(soundManager.isMuted)
        soundManager.play(soundName: "Glass")
        XCTAssertFalse(soundManager.isPlaying, "全局静音开启时常规播放应被拦截")
        
        // 恢复正常
        soundManager.isMuted = false
        XCTAssertFalse(soundManager.isMuted)
        
        // 验证提醒形式改名正名
        XCTAssertEqual(AlertStyle.none.displayName, "不提醒（完全静默）")
        XCTAssertEqual(AlertStyle.both.displayName, "弹窗与声音")
        XCTAssertEqual(AlertStyle.sound.displayName, "仅声音")
        XCTAssertEqual(AlertStyle.popup.displayName, "仅弹窗")
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
    
    // MARK: - 测试 14: 打断恢复策略 (区分专注被打断 vs 休息被打断)
    func testInterruptionRecoveryStrategy() {
        let preset = Preset(
            name: "RecoveryTest",
            blocks: [
                FlowBlock.makeWork(name: "番茄 1", minutes: 20),
                FlowBlock.makeCountdownRest(name: "短休 1", minutes: 5),
                FlowBlock.makeWork(name: "番茄 2", minutes: 20)
            ],
            workInterruptRecovery: .resume,       // 专注被打断：断点续传
            restInterruptRecovery: .advanceNext   // 休息被打断：推进至下一步（开始新一轮专注）
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
        
        // 专注期间手动待机 (策略: .resume 断点续传)
        engine.enterStandby(reason: .manual)
        XCTAssertEqual(engine.mode, .standby)
        XCTAssertEqual(engine.currentBlockIndex, 0)
        
        // 重新启动：由于策略为 .resume，保留还剩 15 分钟继续倒数
        engine.startCurrentBlock()
        XCTAssertEqual(engine.mode, .working)
        XCTAssertEqual(engine.currentSeconds, 15 * 60)
        
        // 推进到休息阶段 (短休 1)
        simulatedDate.addTimeInterval(15 * 60)
        engine.tick()
        XCTAssertEqual(engine.currentBlockIndex, 1)
        XCTAssertEqual(engine.mode, .resting)
        
        // 休息期间发生待机（策略: .advanceNext 推进至下一步）
        engine.enterStandby(reason: .idle)
        XCTAssertEqual(engine.mode, .standby)
        // 验证已自动切到下一步（番茄 2 专注）
        XCTAssertEqual(engine.currentBlockIndex, 2)
        XCTAssertEqual(engine.currentBlock?.name, "番茄 2")
        
        // 启动番茄 2
        engine.startCurrentBlock()
        XCTAssertEqual(engine.mode, .working)
        XCTAssertEqual(engine.currentSeconds, 20 * 60)
    }
    
    // MARK: - 测试 15: 精确秒级倒计时休息（如看远方 20 秒）
    func testSecondLevelCountdownRest() {
        let preset = Preset(
            name: "20-20-20 Test",
            blocks: [
                FlowBlock.makeWork(name: "专注", minutes: 20),
                FlowBlock.makeCountdownRest(name: "看远方", seconds: 20, message: "看远方 20 秒", sound: "Glass")
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
        
        // 1. 启动工作 20 分钟
        engine.startCurrentBlock()
        XCTAssertEqual(engine.mode, .working)
        
        // 20 分钟到期推进
        simulatedDate.addTimeInterval(20 * 60)
        engine.tick()
        
        // 应当触发 workCompleted 弹窗，并自动推进到看远方休息模块
        XCTAssertEqual(receivedAlerts.count, 1)
        XCTAssertEqual(receivedAlerts.first?.actionType, .workCompleted)
        XCTAssertEqual(engine.mode, .resting)
        XCTAssertEqual(engine.currentBlock?.name, "看远方")
        XCTAssertEqual(engine.currentSeconds, 20)
        XCTAssertEqual(engine.menuBarText, "< 20s")
        
        // 走过 10 秒
        simulatedDate.addTimeInterval(10)
        engine.tick()
        XCTAssertEqual(engine.currentSeconds, 10)
        
        // 走完最后 10 秒
        simulatedDate.addTimeInterval(10)
        engine.tick()
        XCTAssertEqual(engine.currentSeconds, 0)
        XCTAssertEqual(receivedAlerts.count, 2)
        XCTAssertEqual(receivedAlerts.last?.actionType, .restCompleted)
    }
    
    // MARK: - 测试 16: 自由休息（正计时）零中途弹窗保证
    func testFreeStopwatchRestNoAlerts() {
        let preset = Preset(
            name: "FreeRestTest",
            blocks: [
                FlowBlock.makeWork(name: "专注", minutes: 25),
                FlowBlock.makeStopwatchRest(name: "自由休息", enableChimes: false)
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
        
        // 工作结束并进入自由休息
        engine.startCurrentBlock()
        simulatedDate.addTimeInterval(25 * 60)
        engine.tick()
        XCTAssertEqual(engine.mode, .resting)
        XCTAssertEqual(receivedAlerts.count, 1) // 仅工作结束弹了一次
        
        // 在自由休息中度过 30秒、5分钟、20分钟
        simulatedDate.addTimeInterval(30)
        engine.tick()
        XCTAssertEqual(receivedAlerts.count, 1, "自由休息中途绝不能弹窗打扰用户离开屏幕")
        
        simulatedDate.addTimeInterval(5 * 60)
        engine.tick()
        XCTAssertEqual(receivedAlerts.count, 1, "自由休息中途绝不能弹窗打扰用户离开屏幕")
        
        simulatedDate.addTimeInterval(20 * 60)
        engine.tick()
        XCTAssertEqual(receivedAlerts.count, 1, "自由休息全程零弹窗")
        XCTAssertFalse(engine.isPaused, "自由休息中途报时绝不暂停计时器")
    }
    
    // MARK: - 测试 17: 阶段递增轻报时（阈值 22m 开始，40m 截止静默）
    func testIncrementalChimesThresholdAndCutoff() {
        let block = FlowBlock.makeStopwatchRest(
            name: "自由休息",
            enableChimes: true,
            chimeStart: 22,
            chimeEnd: 40
        )
        XCTAssertTrue(block.enableIncrementalChimes)
        XCTAssertEqual(block.chimeStartMinutes, 22)
        XCTAssertEqual(block.chimeEndMinutes, 40)
        
        // 验证报时计算规则:
        // 22分 -> 响 2 下 (22 / 10 = 2)
        // 30分 -> 响 3 下 (30 / 10 = 3)
        // 40分 -> 响 4 下 (40 / 10 = 4)
        // 41分以上 -> 超过截止阈值静默
        func shouldChimeAndCount(atMinute m: Int) -> Int? {
            guard block.enableIncrementalChimes, m >= block.chimeStartMinutes, m <= block.chimeEndMinutes else {
                return nil
            }
            if m == block.chimeStartMinutes || m % 10 == 0 {
                return max(1, m / 10)
            }
            return nil
        }
        
        XCTAssertNil(shouldChimeAndCount(atMinute: 10))
        XCTAssertNil(shouldChimeAndCount(atMinute: 20))
        XCTAssertNil(shouldChimeAndCount(atMinute: 21))
        XCTAssertEqual(shouldChimeAndCount(atMinute: 22), 2)
        XCTAssertNil(shouldChimeAndCount(atMinute: 23))
        XCTAssertEqual(shouldChimeAndCount(atMinute: 30), 3)
        XCTAssertNil(shouldChimeAndCount(atMinute: 35))
        XCTAssertEqual(shouldChimeAndCount(atMinute: 40), 4)
        XCTAssertNil(shouldChimeAndCount(atMinute: 41))
        XCTAssertNil(shouldChimeAndCount(atMinute: 50))
    }
    
    // MARK: - 测试 18: 自由休息截止阈值弹窗提醒与超时自动转待机
    func testStopwatchCutoffAlertAndAutoStandby() {
        let preset = Preset(
            name: "CutoffStandbyTest",
            blocks: [
                FlowBlock.makeWork(name: "专注", minutes: 20),
                FlowBlock.makeStopwatchRest(name: "自由休息", enableChimes: true, chimeStart: 20, chimeEnd: 40, cutoffAction: .alertAndStandby)
            ],
            restMaxMinutes: 45
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
        
        // 1. 跳到休息步并启动
        engine.jumpToBlock(index: 1)
        XCTAssertEqual(engine.mode, .resting)
        XCTAssertEqual(engine.currentBlock?.timingMode, .stopwatch)
        
        // 2. 模拟运行到 40 分钟截止阈值
        simulatedDate.addTimeInterval(40 * 60)
        engine.tick()
        XCTAssertEqual(receivedAlerts.count, 1)
        XCTAssertEqual(receivedAlerts.first?.actionType, .restCompleted)
        XCTAssertEqual(engine.mode, .resting)
        
        // 3. 用户离开工位未按弹窗，经过 3 分钟 (180 秒)
        simulatedDate.addTimeInterval(180)
        engine.tick()
        
        // 验证：已安全自动转入待机模式，绝不在空房间假装专注
        XCTAssertEqual(engine.mode, .standby)
        // 验证：打断恢复策略自动将下一步推进至“专注”
        XCTAssertEqual(engine.currentBlockIndex, 0)
        XCTAssertEqual(engine.currentBlock?.type, .work)
    }
    
    // MARK: - 测试 19: 待机状态下大数字显示（自由休息重置为0，倒计时显示满额预设）
    func testStandbyDisplayFormattedOutput() {
        let preset = Preset(
            name: "DisplayTest",
            blocks: [
                FlowBlock.makeWork(name: "专注", minutes: 25),
                FlowBlock.makeStopwatchRest(name: "自由休息"),
                FlowBlock.makeCountdownRest(name: "远眺", seconds: 20)
            ]
        )
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            userDefaults: mockUserDefaults,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        
        // 初始待机状态：第 0 步是专注 25m
        XCTAssertEqual(engine.mode, .standby)
        XCTAssertEqual(engine.currentBlockIndex, 0)
        XCTAssertEqual(engine.currentSeconds, 25 * 60)
        
        // 验证菜单栏在待机时显示“待命”
        engine.updateMenuBarText()
        XCTAssertEqual(engine.menuBarText, "待命")
    }
    
    // MARK: - 测试 20: 工作结束提醒与「离开工位」主按钮交互防跳过机制
    func testWorkCompletedLeaveDeskAlertActionDoesNotSkipRest() {
        let preset = Preset(
            name: "LeaveDeskAlertTest",
            blocks: [
                FlowBlock.makeWork(name: "专注", minutes: 20), // 默认 autoAdvance: true
                FlowBlock.makeCountdownRest(name: "休息", minutes: 5) // 默认 autoAdvance: false
            ]
        )
        var receivedAlert: AlertTriggerEvent?
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            userDefaults: mockUserDefaults,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        engine.onAlertTriggered = { event in
            receivedAlert = event
        }
        
        // 1. 启动专注
        engine.startCurrentBlock()
        XCTAssertEqual(engine.mode, .working)
        XCTAssertEqual(engine.currentBlockIndex, 0)
        
        // 2. 20 分钟专注时间结束
        simulatedDate.addTimeInterval(20 * 60)
        engine.tick()
        
        // 验证：触发 workCompleted 弹窗，并已正确标记 autoAdvanced = true
        guard let alert = receivedAlert else {
            XCTFail("应当触发提醒事件")
            return
        }
        XCTAssertEqual(alert.actionType, .workCompleted)
        XCTAssertTrue(alert.autoAdvanced)
        XCTAssertEqual(alert.blockIndex, 0)
        
        // 验证：引擎当前已自动处于休息阶段
        XCTAssertEqual(engine.mode, .resting)
        XCTAssertEqual(engine.currentBlockIndex, 1)
        XCTAssertEqual(engine.currentBlock?.name, "休息")
        
        // 3. 用户在弹窗上点击「离开工位」（触发 onPrimaryAction 回调）
        // 模拟 BreakLoop.swift 中的回调逻辑：
        if !alert.autoAdvanced {
            engine.advanceToNextBlock()
        }
        
        // 核心断言：点击「离开工位」后，引擎必须依然保持在休息阶段（.resting），
        // 绝不能错误跳回专注阶段（.working）！
        XCTAssertEqual(engine.mode, .resting)
        XCTAssertEqual(engine.currentBlockIndex, 1)
        XCTAssertEqual(engine.currentBlock?.name, "休息")
    }
    
    // MARK: - 测试 21: 方案 A（稍后提醒 = 专注加时 5 分钟，随后休息时间不受扣减）
    func testSnoozeExtendsWorkAndPreservesFullRest() {
        let preset = Preset(
            name: "SnoozeOptionATest",
            blocks: [
                FlowBlock.makeWork(name: "专注", minutes: 20),
                FlowBlock.makeCountdownRest(name: "短休", minutes: 5)
            ]
        )
        var alertCount = 0
        var lastAlert: AlertTriggerEvent?
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            userDefaults: mockUserDefaults,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        engine.onAlertTriggered = { event in
            alertCount += 1
            lastAlert = event
        }
        
        // 1. 启动专注
        engine.startCurrentBlock()
        XCTAssertEqual(engine.mode, .working)
        
        // 20 分钟时间到
        simulatedDate.addTimeInterval(20 * 60)
        engine.tick()
        XCTAssertEqual(alertCount, 1)
        guard let alert1 = lastAlert else { return XCTFail() }
        
        // 2. 用户点击「稍后 5 分钟」（触发 onSnooze 回调）
        engine.snooze(minutes: alert1.snoozeMinutes, rewindingTo: alert1.autoAdvanced ? alert1.blockIndex : nil)
        
        // 验证：模式切回工作态，倒计时 5 分钟（300秒），索引回溯至专注块
        XCTAssertEqual(engine.mode, .working)
        XCTAssertEqual(engine.currentBlockIndex, 0)
        XCTAssertEqual(engine.currentSeconds, 5 * 60)
        
        // 3. 走过 5 分钟加时
        simulatedDate.addTimeInterval(5 * 60)
        engine.tick()
        
        // 验证：加时结束，再次弹窗提醒休息
        XCTAssertEqual(alertCount, 2)
        XCTAssertEqual(lastAlert?.actionType, .workCompleted)
        
        // 验证：由于开启了自动推进，此时已进入休息，且休息拥有满额 5 分钟（300秒），未被扣除一秒
        XCTAssertEqual(engine.mode, .resting)
        XCTAssertEqual(engine.currentBlockIndex, 1)
        XCTAssertEqual(engine.currentSeconds, 5 * 60)
    }
    
    // MARK: - 测试 22: 正计时向下取整（0~59秒显示 > 0m）与打断恢复文案无括号极简化
    func testStopwatchFloorRoundingAndCleanRecoveryNames() {
        // 1. 文案测试：打断恢复策略移除冗余括号与硬编码
        XCTAssertEqual(InterruptRecovery.resetCurrent.displayName, "重置本步")
        XCTAssertEqual(InterruptRecovery.resume.displayName, "断点续传")
        XCTAssertEqual(InterruptRecovery.advanceNext.displayName, "推进至下一步")
        XCTAssertEqual(InterruptRecovery.resetCycle.displayName, "重置整轮")
        
        // 即使下一步也是休息，仍然通用表达为“推进至下一步”
        XCTAssertEqual(InterruptRecovery.advanceNext.displayName(for: .rest), "推进至下一步")
        XCTAssertEqual(InterruptRecovery.advanceNext.displayName(for: .work), "推进至下一步")
        
        // 2. 正计时取整逻辑测试：
        let preset = Preset(
            name: "StopwatchFloorTest",
            blocks: [
                FlowBlock.makeStopwatchRest(name: "自由休息")
            ]
        )
        let engine = TimerEngine(
            preset: preset,
            sessionStore: sessionStore,
            userDefaults: mockUserDefaults,
            nowProvider: { [weak self] in self?.simulatedDate ?? Date() }
        )
        engine.startCurrentBlock()
        XCTAssertEqual(engine.mode, .resting)
        
        // 刚刚开始走时 0 秒 -> > 0m
        engine.tick()
        XCTAssertEqual(engine.menuBarText, "> 0m")
        
        // 走过 50 秒（截图中的真实场景）-> 依然是 > 0m（向下取整，绝不误显为 > 1m）
        simulatedDate.addTimeInterval(50)
        engine.tick()
        XCTAssertEqual(engine.menuBarText, "> 0m")
        
        // 走过满 60 秒 -> > 1m
        simulatedDate.addTimeInterval(10)
        engine.tick()
        XCTAssertEqual(engine.menuBarText, "> 1m")
    }
}
