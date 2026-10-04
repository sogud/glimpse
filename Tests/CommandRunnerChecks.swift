import Foundation

@main
struct CommandRunnerChecks {
    static func main() throws {
        do {
            _ = try CommandRunner.run("/usr/bin/perl", arguments: ["-e", "print STDERR 'x' x 200000; exit 1"], timeout: 3)
            fatalError("大量 stderr 不能被当作成功")
        } catch {
            precondition(error.localizedDescription.contains(String(repeating: "x", count: 100)), "子进程错误必须保留，不能卡在管道")
        }
        let started = Date()
        do {
            _ = try CommandRunner.run("/bin/sleep", arguments: ["10"], timeout: 0.1)
            fatalError("超时必须结束自己启动的子进程")
        } catch {
            precondition(Date().timeIntervalSince(started) < 2, "超时后必须及时返回")
        }
        print("Command runner checks passed")
    }
}
