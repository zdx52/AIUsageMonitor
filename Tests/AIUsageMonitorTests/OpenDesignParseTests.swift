import XCTest
@testable import AIUsageMonitor

/// 用真实 vela `billing preflight` 输出样本校验解析。
final class OpenDesignParseTests: XCTestCase {

    private let sample = """
    {"schemaVersion":1,"workspaceId":"ebovu8r07cuh4ekwtceqtgx2","workspaceMemberId":"n6x3yskoe9rifk593wyex6f1","modelId":null,"generatedAt":"2026-10-22T15:44:10.131Z","balanceUsd":"1.0000","codingPlan":{"workspaceId":"ebovu8r07cuh4ekwtceqtgx2","generatedAt":"2026-10-22T15:44:10.129Z","eligible":true,"tier":"go","windows":[{"policyId":"p1","durationSeconds":18000,"resetMode":"anchored_recurring","usedCredits":"262","limitCredits":"50000","remainingCredits":"49738","windowStart":"2026-10-22T15:22:25.000Z","resetsAt":"2026-10-22T20:22:25.000Z"},{"policyId":"p2","durationSeconds":604800,"resetMode":"anchored_recurring","usedCredits":"262","limitCredits":"150000","remainingCredits":"149738","windowStart":"2026-10-22T15:22:25.000Z","resetsAt":"2026-10-29T15:22:25.000Z"}]},"modelCovered":null,"funding":"wallet"}
    """.data(using: .utf8)!

    func testParsesWindows() {
        let usage = OpenDesignUsage.from(preflight: sample)
        XCTAssertNotNil(usage)
        XCTAssertEqual(usage?.tier, "go")
        XCTAssertEqual(usage?.balanceUsd, 1.0)
        XCTAssertEqual(usage?.windows.count, 2)

        let fiveHour = usage?.windows.first { $0.seconds == 18000 }
        XCTAssertEqual(fiveHour?.usedCredits, 262)
        XCTAssertEqual(fiveHour?.limitCredits, 50000)
        XCTAssertEqual(fiveHour?.usedPercent ?? -1, 0.524, accuracy: 0.001)
        XCTAssertEqual(fiveHour?.label, "5小时")
        XCTAssertNotNil(fiveHour?.resetsAt)

        XCTAssertEqual(usage?.windows.first { $0.seconds == 604800 }?.label, "7天")
    }

    func testRejectsEmptyWindows() {
        let empty = #"{"balanceUsd":"0","codingPlan":{"tier":"go","windows":[]}}"#.data(using: .utf8)!
        XCTAssertNil(OpenDesignUsage.from(preflight: empty))
    }

    func testRejectsGarbage() {
        XCTAssertNil(OpenDesignUsage.from(preflight: Data("not json".utf8)))
    }

    /// 本机无 Open Design 时跳过；装了就必须能定位到 vela 和 workspace id。
    func testLiveResolvesVelaAndWorkspace() throws {
        guard let vela = OpenDesignService.velaPath() else {
            throw XCTSkip("本机未安装 Open Design")
        }
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: vela))
        XCTAssertNotNil(OpenDesignService.workspaceId())
    }

    /// 端到端：真跑 vela，能拿到窗口数据（需本机已登录 Open Design）。
    func testLiveFetchUsage() async throws {
        guard OpenDesignService.velaPath() != nil else {
            throw XCTSkip("本机未安装 Open Design")
        }
        let usage = await OpenDesignService.fetchUsage()
        try XCTSkipIf(usage == nil, "本机 Open Design 未登录或无额度数据")
        XCTAssertFalse(usage!.windows.isEmpty)
        XCTAssertTrue((0...100).contains(usage!.maxUsedPercent))
    }

    /// 上游偶发 EOF：前两次失败、第三次成功必须重试拿到数据。
    func testRetriesUntilSuccess() async throws {
        guard OpenDesignService.velaPath() != nil else {
            throw XCTSkip("本机未安装 Open Design")
        }
        var calls = 0
        let usage = await OpenDesignService.fetchUsage(attempts: 3) { _, _ in
            calls += 1
            return calls < 3 ? nil : self.sample
        }
        XCTAssertEqual(calls, 3)
        XCTAssertNotNil(usage)
        XCTAssertEqual(usage?.windows.count, 2)
    }

    /// 全失败时正好试满 attempts 次并返回 nil（交给上层保留旧数据）。
    func testGivesUpAfterAttempts() async throws {
        guard OpenDesignService.velaPath() != nil else {
            throw XCTSkip("本机未安装 Open Design")
        }
        var calls = 0
        let usage = await OpenDesignService.fetchUsage(attempts: 2) { _, _ in
            calls += 1
            return nil
        }
        XCTAssertEqual(calls, 2)
        XCTAssertNil(usage)
    }
}
