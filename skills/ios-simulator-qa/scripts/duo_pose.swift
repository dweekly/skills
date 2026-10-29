// duo_pose: set or read the fold pose of an iPhone Duo simulator from the command line.
//
//   duo-pose <UDID> get | closed | partial | open
//
// Xcode 27.1 has no supported pose control (simctl and XCTest have none); the only control is the
// row of buttons under the device in Device Hub. Device Hub sends a vendor-defined HID event that
// carries a hinge angle; this tool sends the same event from the Mac, then confirms the result three
// ways: the hinge state SpringBoard logs (Closed, PartiallyOpen, OpenFlat), SpringBoard's display
// transition having completed, and screenshots of both integrated displays showing the expected one
// lit. The path does not go through Device Hub's process, but every test so far ran with Device
// Hub open; running without it is untested.
//
// Mechanism (all private and undocumented, so expect it to break on a new Xcode or runtime):
//   1. CoreSimulator (private framework): SimServiceContext -> default device set -> SimDevice,
//      then -[SimDevice lookup:error:] for the Mach service
//      "com.apple.coredevice.feature.remote.hid.vendordefined" inside the booted simulator.
//   2. libxpc SPI: xpc_endpoint_create_mach_port_4sim wraps that port, and
//      xpc_connection_enable_sim2host_4sim marks the connection as host-to-simulator.
//   3. Message: messageType "IndigoVendorDefinedEvent", featureIdentifier (the service name), and a
//      payload of usagePage 0xFF61, usage 91, version 0 and data, where data is an IOKit binary
//      property list (made here with the public IOCFSerialize) of
//      { type: "range", value: <degrees>, source: "hinge-slider-control",
//        provider: "com.apple.Virtualization.VirtualMachines" }.
//      A second message { isBarrier: true } is answered once the first has been dispatched.
//   In the simulator, dtuhidd turns that into a HID event, locationd reads the hinge angle and
//   SpringBoard moves the UI between the outer and inner displays.
//
// Credit: the event, its payload and the 4sim connection were worked out and published by
// tosbaha/duo-fold-control (MIT, https://github.com/tosbaha/duo-fold-control) and
// michael-palmes/offsider PR #87 (MIT, https://github.com/michael-palmes/offsider/pull/87). This
// is an independent implementation written from their descriptions; no code was copied.
// Do not "fix" a pose by powering a display off with `simctl io screenConfig`: that blanks the
// framebuffer without folding (mobile-dev-inc/maestro#3617).

import CoreGraphics
import Darwin
import Foundation
import ImageIO
import IOKit
import XPC

// MARK: - Output and failure

enum Exit: Int32 {
    case ok = 0
    case unconfirmed = 1  // the event was sent but the pose could not be confirmed
    case usage = 2
    case environment = 3  // wrong device, not booted, toolchain or private interface missing
}

func fail(_ code: Exit, _ message: String) -> Never {
    FileHandle.standardError.write(Data("duo-pose: \(message)\n".utf8))
    exit(code.rawValue)
}

func note(_ message: String) {
    if ProcessInfo.processInfo.environment["DUO_POSE_VERBOSE"] != nil {
        FileHandle.standardError.write(Data("duo-pose: \(message)\n".utf8))
    }
}

// MARK: - Poses

enum Pose: String, CaseIterable {
    case closed, partial, open

    // Hinge angle in degrees sent for each pose: 0 is fully closed, 180 flat, and 130 sits well
    // inside the partially open band (SpringBoard logs it as about 127.8 degrees).
    var degrees: Double {
        switch self {
        case .closed: return 0
        case .partial: return 130
        case .open: return 180
        }
    }

    // Which display SpringBoard drives in this pose.
    var expectsInner: Bool { self != .closed }

    // CoreMotion's name for the pose, as SpringBoard logs it.
    var hingeState: String {
        switch self {
        case .closed: return "Closed"
        case .partial: return "PartiallyOpen"
        case .open: return "OpenFlat"
        }
    }

    init?(hingeState: String) {
        guard let p = Pose.allCases.first(where: { $0.hingeState == hingeState }) else { return nil }
        self = p
    }
}

// MARK: - Shell helpers

struct Result {
    let status: Int32
    let out: String
    let err: String
}

@discardableResult
func run(_ args: [String], timeout: TimeInterval = 60) -> Result {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    p.arguments = args
    let outPipe = Pipe(), errPipe = Pipe()
    p.standardOutput = outPipe
    p.standardError = errPipe
    do { try p.run() } catch { return Result(status: -1, out: "", err: "\(error)") }
    // Read before waiting so a large output cannot fill the pipe and stall the child.
    var outData = Data(), errData = Data()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    group.enter()
    DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline { usleep(50_000) }
    if p.isRunning { p.terminate() }  // only the child this process started
    p.waitUntilExit()
    group.wait()
    return Result(status: p.terminationStatus,
                  out: String(decoding: outData, as: UTF8.self),
                  err: String(decoding: errData, as: UTF8.self))
}

// MARK: - Device checks (public simctl)

struct DeviceInfo {
    let name: String
    let state: String
    let typeIdentifier: String
    let runtime: String
    let bootedAt: String?  // simctl's lastUsedAt, which is the boot time for a booted device
}

func describeDevice(_ udid: String) -> DeviceInfo {
    let r = run(["simctl", "list", "devices", "--json"])
    guard r.status == 0,
          let json = try? JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any],
          let groups = json["devices"] as? [String: [[String: Any]]]
    else { fail(.environment, "could not list simulators: \(r.err.trimmingCharacters(in: .whitespacesAndNewlines))") }
    for (runtime, devices) in groups {
        for d in devices where (d["udid"] as? String)?.caseInsensitiveCompare(udid) == .orderedSame {
            return DeviceInfo(name: d["name"] as? String ?? "?",
                              state: d["state"] as? String ?? "?",
                              typeIdentifier: d["deviceTypeIdentifier"] as? String ?? "?",
                              runtime: runtime,
                              bootedAt: d["lastUsedAt"] as? String)
        }
    }
    fail(.environment, "no simulator with UDID \(udid) in the default device set")
}

// MARK: - Display check (public simctl io)

struct Displays {
    let outer: String  // screen IDs for `simctl io screenshot --display=`
    let inner: String
}

func findDisplays(_ udid: String) -> Displays {
    let r = run(["simctl", "io", udid, "enumerate"])
    guard r.status == 0 else { fail(.environment, "simctl io enumerate failed: \(r.err)") }
    // Xcode 27.1 lists each connected screen as a block starting "Screen ID: n" with
    // "Screen Type: Integrated" and "Pixel Size: {w, h}". The Duo has two integrated screens; the
    // larger is the inner one.
    var screens: [(id: String, area: Int)] = []
    for block in r.out.components(separatedBy: "Screen ID:").dropFirst() {
        let lines = block.split(separator: "\n")
        guard let id = lines.first?.trimmingCharacters(in: .whitespaces), Int(id) != nil,
              block.range(of: #"Screen Type:\s*Integrated\b"#, options: .regularExpression) != nil,
              let sizeRange = block.range(of: #"Pixel Size:\s*\{(\d+),\s*(\d+)\}"#, options: .regularExpression)
        else { continue }
        let nums = block[sizeRange].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard nums.count == 2 else { continue }
        screens.append((id, nums[0] * nums[1]))
    }
    guard screens.count == 2 else {
        fail(.environment, "expected two integrated screens in `simctl io \(udid) enumerate`, found \(screens.count); the enumerate format may have changed")
    }
    screens.sort { $0.area < $1.area }
    return Displays(outer: screens[0].id, inner: screens[1].id)
}

// Brightest channel value (0-255) over a downsampled copy of the image; a display SpringBoard is
// not driving captures as solid black.
func peakBrightness(_ url: URL) -> Int? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let side = 64
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let drawn: Bool = pixels.withUnsafeMutableBytes { buf in
        guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return true
    }
    guard drawn else { return nil }
    var peak = 0
    for i in stride(from: 0, to: pixels.count, by: 4) {
        peak = max(peak, Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }
    return peak
}

enum Lit: String { case outer, inner, both, neither, error }

let litThreshold = 24

// Screenshot both integrated displays (in parallel) and report which one shows content.
func litDisplay(_ udid: String, _ displays: Displays, in dir: URL) -> (Lit, String) {
    let shots = [("outer", displays.outer), ("inner", displays.inner)]
    var peaks: [String: Int] = [:]
    var errors: [String] = []
    let lock = NSLock()
    DispatchQueue.concurrentPerform(iterations: shots.count) { i in
        let (label, id) = shots[i]
        let url = dir.appendingPathComponent("\(label)-\(UUID().uuidString).png")
        let r = run(["simctl", "io", udid, "screenshot", "--display=\(id)", url.path], timeout: 30)
        let peak = r.status == 0 ? peakBrightness(url) : nil
        try? FileManager.default.removeItem(at: url)
        lock.lock()
        if let peak { peaks[label] = peak } else {
            errors.append("\(label) display \(id): \(r.status == 0 ? "unreadable image" : r.err.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        lock.unlock()
    }
    let detail = "peak brightness outer=\(peaks["outer"].map(String.init) ?? "n/a") inner=\(peaks["inner"].map(String.init) ?? "n/a")"
    if !errors.isEmpty { return (.error, errors.joined(separator: "; ")) }
    let outerLit = peaks["outer"]! > litThreshold, innerLit = peaks["inner"]! > litThreshold
    switch (outerLit, innerLit) {
    case (true, false): return (.outer, detail)
    case (false, true): return (.inner, detail)
    case (true, true): return (.both, detail)
    case (false, false): return (.neither, detail)
    }
}

// MARK: - SpringBoard's own record (public simctl spawn + log)

struct SpringBoardState {
    // Last "hingeState:" CoreMotion reported to SpringBoard (Closed, PartiallyOpen, OpenFlat).
    let hingeState: String?
    // false while SpringBoard's last display-content transition has STARTING but no COMPLETED.
    let settled: Bool
}

// SpringBoard logs each pose CoreMotion reports to it as
// "Sending MagicPose event to client: CMMagicPoseEvent ... hingeState:<state>", including Closed at
// boot; re-sending the current angle logs nothing, so the latest line since boot is the current
// state. It logs each move of content between the displays as "STARTING: ..." and "COMPLETED: ..."
// (category DisplayContentMode). Returns nil when the log cannot be read.
func springBoardState(_ udid: String, bootedAt: String?) -> SpringBoardState? {
    var args = ["simctl", "spawn", udid, "log", "show", "--style", "compact", "--predicate",
                #"process == "SpringBoard" AND (eventMessage CONTAINS "CMMagicPoseEvent" OR "#
                + #"(category == "DisplayContentMode" AND (eventMessage BEGINSWITH "STARTING:" OR eventMessage BEGINSWITH "COMPLETED:")))"#]
    if let bootedAt, let boot = ISO8601DateFormatter().date(from: bootedAt) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        args += ["--start", f.string(from: boot.addingTimeInterval(-60))]
    } else {
        args += ["--last", "1d"]
    }
    let r = run(args, timeout: 60)
    guard r.status == 0 else { return nil }
    var state: String?
    var settled = true
    for line in r.out.split(separator: "\n") {
        if let range = line.range(of: #"hingeState:[A-Za-z]+"#, options: .regularExpression) {
            state = String(line[range].dropFirst("hingeState:".count))
        } else if line.contains("] STARTING:") {
            settled = false
        } else if line.contains("] COMPLETED:") {
            settled = true
        }
    }
    return SpringBoardState(hingeState: state, settled: settled)
}

// MARK: - Sending the hinge event (private CoreSimulator and libxpc SPI)

let serviceName = "com.apple.coredevice.feature.remote.hid.vendordefined"

func developerDir() -> String {
    if let d = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !d.isEmpty { return d }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
    p.arguments = ["-p"]
    let pipe = Pipe()
    p.standardOutput = pipe
    try? p.run()
    p.waitUntilExit()
    let s = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return s.isEmpty ? "/Applications/Xcode.app/Contents/Developer" : s
}

func interfaceChanged(_ what: String) -> Never {
    fail(.environment, "\(what). The private simulator interface this tool relies on has probably changed in this Xcode or macOS; see the header of duo_pose.swift and recheck the reference projects.")
}

typealias ObjCObjectWithError = @convention(c) (AnyObject, Selector, AnyObject?, UnsafeMutablePointer<Unmanaged<NSError>?>?) -> Unmanaged<AnyObject>?
typealias ObjCObjectErrorOnly = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<Unmanaged<NSError>?>?) -> Unmanaged<AnyObject>?
typealias ObjCPortWithError = @convention(c) (AnyObject, Selector, AnyObject, UnsafeMutablePointer<Unmanaged<NSError>?>?) -> mach_port_t

func implementation<T>(_ target: AnyObject, _ name: String, as: T.Type) -> (Selector, T) {
    let sel = NSSelectorFromString(name)
    guard target.responds(to: sel), let imp = (target as? NSObject)?.method(for: sel) ?? nil else {
        interfaceChanged("\(type(of: target)) no longer responds to \(name)")
    }
    return (sel, unsafeBitCast(imp, to: T.self))
}

func simDevice(_ udid: String) -> AnyObject {
    let path = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"
    guard dlopen(path, RTLD_NOW) != nil else { interfaceChanged("could not load \(path)") }
    guard let contextClass: AnyObject = NSClassFromString("SimServiceContext") else {
        interfaceChanged("CoreSimulator has no SimServiceContext class")
    }
    var err: Unmanaged<NSError>?
    let (s1, sharedContext) = implementation(contextClass, "sharedServiceContextForDeveloperDir:error:", as: ObjCObjectWithError.self)
    guard let context = sharedContext(contextClass, s1, developerDir() as NSString, &err)?.takeUnretainedValue() else {
        interfaceChanged("SimServiceContext failed: \(err?.takeUnretainedValue().localizedDescription ?? "no error")")
    }
    let (s2, defaultSet) = implementation(context, "defaultDeviceSetWithError:", as: ObjCObjectErrorOnly.self)
    guard let set = defaultSet(context, s2, &err)?.takeUnretainedValue() as? NSObject,
          let devices = set.value(forKey: "devices") as? [NSObject] else {
        interfaceChanged("could not read the default device set: \(err?.takeUnretainedValue().localizedDescription ?? "no error")")
    }
    for d in devices {
        if let id = d.value(forKey: "UDID") as? UUID, id.uuidString.caseInsensitiveCompare(udid) == .orderedSame {
            return d
        }
    }
    fail(.environment, "CoreSimulator does not list \(udid) in the default device set")
}

func errorText(_ event: xpc_object_t) -> String {
    guard let c = xpc_dictionary_get_string(event, XPC_ERROR_KEY_DESCRIPTION) else { return "unknown" }
    return String(cString: c)
}

final class HingeConnection {
    let connection: xpc_connection_t

    init(udid: String) {
        let device = simDevice(udid)
        var err: Unmanaged<NSError>?
        let (sel, lookup) = implementation(device, "lookup:error:", as: ObjCPortWithError.self)
        let port = lookup(device, sel, serviceName as NSString, &err)
        guard port != 0 else {
            interfaceChanged("the simulator does not publish \(serviceName) (\(err?.takeUnretainedValue().localizedDescription ?? "no error"))")
        }
        guard let createSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "xpc_endpoint_create_mach_port_4sim"),
              let enableSym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "xpc_connection_enable_sim2host_4sim")
        else { interfaceChanged("libxpc no longer exports the *_4sim functions") }
        typealias CreateEndpoint = @convention(c) (mach_port_t) -> UnsafeMutableRawPointer?
        typealias EnableSim2Host = @convention(c) (UnsafeMutableRawPointer) -> Void
        guard let raw = unsafeBitCast(createSym, to: CreateEndpoint.self)(port) else {
            interfaceChanged("xpc_endpoint_create_mach_port_4sim returned nothing")
        }
        let endpoint = Unmanaged<AnyObject>.fromOpaque(raw).takeRetainedValue() as! xpc_endpoint_t
        connection = xpc_connection_create_from_endpoint(endpoint)
        unsafeBitCast(enableSym, to: EnableSim2Host.self)(Unmanaged.passUnretained(connection as AnyObject).toOpaque())
        xpc_connection_set_event_handler(connection) { event in
            if xpc_get_type(event) == XPC_TYPE_ERROR, !xpc_equal(event, XPC_ERROR_CONNECTION_INVALID) {
                note("connection event: \(errorText(event))")
            }
        }
        xpc_connection_resume(connection)
    }

    // Sends one hinge event and waits until the service has dispatched it.
    func send(degrees: Double) {
        let hinge: NSDictionary = ["type": "range", "value": NSNumber(value: degrees),
                                   "source": "hinge-slider-control",
                                   "provider": "com.apple.Virtualization.VirtualMachines"]
        let data = IOCFSerialize(hinge, CFOptionFlags(kIOCFSerializeToBinary)) as Data? ?? Data()
        guard !data.isEmpty else { fail(.environment, "IOCFSerialize could not encode the hinge payload") }

        let payload = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(payload, "usagePage", 0xFF61)
        xpc_dictionary_set_uint64(payload, "usage", 91)
        xpc_dictionary_set_uint64(payload, "version", 0)
        data.withUnsafeBytes { xpc_dictionary_set_data(payload, "data", $0.baseAddress!, data.count) }

        let message = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(message, "messageType", "IndigoVendorDefinedEvent")
        xpc_dictionary_set_string(message, "featureIdentifier", serviceName)
        xpc_dictionary_set_value(message, "payload", payload)
        xpc_connection_send_message(connection, message)

        let barrier = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_bool(barrier, "isBarrier", true)
        let reply = xpc_connection_send_message_with_reply_sync(connection, barrier)
        if xpc_get_type(reply) == XPC_TYPE_ERROR {
            let why = errorText(reply)
            interfaceChanged("the hinge service rejected the event (\(why))")
        }
    }

    func close() { xpc_connection_cancel(connection) }
}

// MARK: - Commands

// Sending a new angle while SpringBoard is still completing a stalled transition can wedge it: the
// hinge state keeps changing but the displays never follow again. Restarting SpringBoard cleared
// that in testing; a reboot also does (and resets the pose to closed).
let wedgeAdvice = """
SpringBoard's fold transition looks wedged (hinge state changes, displays do not follow). \
Recover with `xcrun simctl spawn <UDID> launchctl kickstart -k user/$(id -u)/com.apple.SpringBoard` \
(restarts the home screen and the apps it hosts) or by rebooting the simulator, then retry.
"""

// A pose counts only when three observations agree: SpringBoard's last logged hinge state, its
// last display transition having completed, and the display that is actually lit.
struct Observation {
    let lit: Lit
    let litDetail: String
    let springBoard: SpringBoardState?

    var pose: Pose? {
        guard let sb = springBoard, sb.settled, let hs = sb.hingeState, let p = Pose(hingeState: hs) else { return nil }
        return lit == (p.expectsInner ? .inner : .outer) ? p : nil
    }

    var summary: String {
        let sb = springBoard.map { "hingeState \($0.hingeState ?? "not logged"), display transition \($0.settled ? "completed" : "NOT completed")" }
        return "lit display \(lit.rawValue) (\(litDetail)), SpringBoard \(sb ?? "log unreadable")"
    }
}

func observe(_ udid: String, _ displays: Displays, _ info: DeviceInfo, scratch: URL) -> Observation {
    let (lit, detail) = litDisplay(udid, displays, in: scratch)
    let o = Observation(lit: lit, litDetail: detail, springBoard: springBoardState(udid, bootedAt: info.bootedAt))
    note(o.summary)
    return o
}

let args = CommandLine.arguments
let usage = """
usage: duo-pose <UDID> get|closed|partial|open
  get      print the current pose, or "unknown" (exit 1) when the lit display, the hinge
           state SpringBoard last logged and its last display transition do not agree
  closed   fold shut: the outer display is active
  partial  partially open (hinge at 130 degrees): the inner display is active
  open     fully open, flat (180 degrees): the inner display is active
Requires an explicit UDID of a booted iPhone Duo simulator. Exits 0 only when the pose is
confirmed three ways: SpringBoard has logged the matching hinge state, its last display
transition has completed, and screenshots of both displays show the expected one lit. 1 when it is not confirmed; 2 for usage errors;
3 when the device, toolchain or private interface is wrong.
Environment: DUO_POSE_TIMEOUT (seconds to wait for confirmation, default 30),
DUO_POSE_VERBOSE=1 for progress on stderr.
"""
guard args.count == 3 else { fail(.usage, "\n" + usage) }
let udid = args[1], command = args[2].lowercased()
guard udid.range(of: #"^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$"#, options: .regularExpression) != nil else {
    fail(.usage, "the first argument must be an exact simulator UDID, never a name, \"booted\" or \"all\"\n" + usage)
}
guard command == "get" || Pose(rawValue: command) != nil else { fail(.usage, "unknown command \"\(args[2])\"\n" + usage) }

let info = describeDevice(udid)
guard info.typeIdentifier.hasSuffix(".iPhone-Duo") else {
    fail(.environment, "\(udid) (\(info.name)) is a \(info.typeIdentifier), not an iPhone Duo")
}
guard info.state == "Booted" else { fail(.environment, "\(udid) (\(info.name)) is \(info.state); boot it first") }

let displays = findDisplays(udid)
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("duo-pose-\(getpid())")
try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

if command == "get" {
    let o = observe(udid, displays, info, scratch: scratch)
    try? FileManager.default.removeItem(at: scratch)
    if let pose = o.pose {
        print(pose.rawValue)
        exit(Exit.ok.rawValue)
    }
    print("unknown")
    fail(.unconfirmed, "the displays and SpringBoard's state disagree or are unreadable: \(o.summary)")
}

let pose = Pose(rawValue: command)!
let timeout = Double(ProcessInfo.processInfo.environment["DUO_POSE_TIMEOUT"] ?? "") ?? 30
let started = Date()
let hinge = HingeConnection(udid: udid)

// SpringBoard moves content between displays as a continuous transition and completes a stalled
// one only at an intermediate angle. A single jump from closed straight to 180 degrees starts a
// transition that never completes, and SpringBoard then ignores the next close (seen on iOS 27.1).
// Device Hub's slider streams intermediate angles; this tool instead stops at the partial angle and
// waits for SpringBoard to log the transition COMPLETED whenever it is opening from closed, or a
// transition is still open (left by a direct jump, perhaps from another tool). Not sending the
// final angle until then matters: interrupting a completing transition can wedge SpringBoard.
let before = springBoardState(udid, bootedAt: info.bootedAt)
let openFromClosed = pose == .open && before?.hingeState != Pose.partial.hingeState && before?.hingeState != Pose.open.hingeState
let stalled = before?.settled != true
if pose != .partial, openFromClosed || stalled {
    hinge.send(degrees: Pose.partial.degrees)
    note("sent waypoint \(Pose.partial.degrees) degrees (SpringBoard hingeState \(before?.hingeState ?? "unknown"), last transition \(stalled ? "not completed" : "completed"))")
    var waypointSettled = false
    while Date().timeIntervalSince(started) < timeout / 2 {
        usleep(300_000)
        if let sb = springBoardState(udid, bootedAt: info.bootedAt), sb.settled, sb.hingeState == Pose.partial.hingeState {
            waypointSettled = true
            break
        }
    }
    if !waypointSettled {
        hinge.close()
        fail(.unconfirmed, "SpringBoard did not complete the display transition at the \(Pose.partial.degrees)-degree waypoint, so the final angle was not sent. " + wedgeAdvice)
    }
    note("waypoint settled")
}
hinge.send(degrees: pose.degrees)
note("sent hinge \(pose.degrees) degrees to \(udid) (\(info.name), \(info.runtime))")

// Keep the connection open while confirming, so the event is not dropped with it.
var last: Observation?
while Date().timeIntervalSince(started) < timeout {
    let o = observe(udid, displays, info, scratch: scratch)
    last = o
    if o.pose == pose { break }
    usleep(500_000)
}
hinge.close()
try? FileManager.default.removeItem(at: scratch)

if let last, last.pose == pose {
    print(pose.rawValue)
    exit(Exit.ok.rawValue)
}
fail(.unconfirmed, """
sent \(pose.rawValue) (\(pose.degrees) degrees, expecting hingeState \(pose.hingeState) on the \
\(pose.expectsInner ? "inner" : "outer") display) but could not confirm it within \(Int(timeout))s; \
last saw \(last?.summary ?? "nothing"). \(last?.springBoard?.hingeState == pose.hingeState && last?.springBoard?.settled == false ? wedgeAdvice + " " : "")If the hinge state never changes, the hinge event or its \
handling in the simulator has probably changed in this Xcode or runtime (see the header of \
duo_pose.swift). If it changed but the display did not, or the log line is missing, the \
confirmation signals have changed instead. If the switch is just slow, raise DUO_POSE_TIMEOUT.
""")
