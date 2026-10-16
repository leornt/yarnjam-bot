import CoreGraphics
import Foundation

@MainActor
final class Session {
    private var working = false

    func press(_ key: Int) {
        guard key == 1 else { return }
        if working {
            print("Still reading the screen.")
            return
        }
        working = true
        Task {
            await playOneMove()
            working = false
        }
    }

    /// One press captures the screen, reads the board, and clicks the first safe yarn.
    private func playOneMove() async {
        do {
            let shots = try await captureDisplays()
            saveShots(shots)
            guard let board = firstBoard(in: shots) else {
                print("I don't see the game. Keep the board visible and press 1 again.")
                print("Saved what was captured to debug/last-capture.png.")
                return
            }
            try? FileManager.default.createDirectory(atPath: "debug", withIntermediateDirectories: true)
            writeOverlay(board, to: "debug/last-analysis.png")
            print(describe(board: board))
            guard let target = board.targets.first else {
                print("No safe target. Nothing was clicked.")
                return
            }
            guard let map = board.map else {
                print("No display mapping for this reading, so nothing was clicked.")
                return
            }
            let yarn = target.yarn
            let point = map.globalPoint(analysisX: yarn.clickPoint.x, analysisY: yarn.clickPoint.y)
            // Let the browser see the pointer on the yarn before the click.
            movePointer(to: point)
            try? await Task.sleep(nanoseconds: 80_000_000)
            clickPointer(at: point)
            print(
                String(
                    format: "Clicked %@ yarn, %@. (%.0f, %.0f)",
                    yarn.average.hex,
                    target.label,
                    point.x,
                    point.y
                )
            )
            print("Press 1 again after the board settles.")
        } catch {
            print("Screen capture failed: \(error)")
            print("Grant Screen Recording to this terminal, then press 1 again.")
        }
    }

    private func firstBoard(in shots: [Shot]) -> BoardReading? {
        for shot in shots {
            if let board = Analyzer().read(shot: shot) {
                return board
            }
        }
        return nil
    }
}

private func analyzeImage(path: String) throws {
    let shot = try loadShot(path: path)
    guard let board = Analyzer().read(shot: shot) else {
        print("No game board found in \(path).")
        exit(1)
    }
    try? FileManager.default.createDirectory(atPath: "debug", withIntermediateDirectories: true)
    writeOverlay(board, to: "debug/last-analysis.png")
    print(describe(board: board))
}

private func saveShots(_ shots: [Shot]) {
    try? FileManager.default.createDirectory(atPath: "debug", withIntermediateDirectories: true)
    for (index, shot) in shots.enumerated() {
        let name = shots.count == 1 ? "debug/last-capture.png" : "debug/last-capture-\(index).png"
        writeCGImage(shot.image, to: name)
    }
}

private func banner() {
    print(
        """
        Yarn Jam bot
        Waiting. Nothing runs until you press 1.
          1  capture, analyze, move to the next yarn, and click
        One press is one click. Press 1 again after the board settles.
        """
    )
}

@main
struct YarnJamBot {
    static func main() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--image") {
            guard flag + 1 < arguments.count else {
                print("Usage: YarnJamBot --image path")
                exit(2)
            }
            do {
                try analyzeImage(path: arguments[flag + 1])
            } catch {
                print(error)
                exit(1)
            }
            return
        }

        banner()
        if !CGPreflightScreenCaptureAccess() {
            print("Screen Recording is not granted yet. Allow it for this terminal if macOS asks.")
            _ = CGRequestScreenCaptureAccess()
        }
        if !accessibilityIsTrusted(prompt: true) {
            print("Accessibility is not granted. Allow it for this terminal, then start the bot again.")
        }

        let session = MainActor.assumeIsolated { Session() }
        let monitor = HotkeyMonitor()
        monitor.onKey = { key in
            Task { @MainActor in
                session.press(key)
            }
        }
        guard monitor.start() else {
            print("Could not listen for keys. Grant Accessibility to this terminal and start the bot again.")
            exit(1)
        }
        print("Listening. Press 1 with the game visible.")
        CFRunLoopRun()
    }
}
