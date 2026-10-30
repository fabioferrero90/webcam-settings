import SwiftUI
import AVFoundation

func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

// MARK: - UVC controls

enum Kind { case slider, auto, powerLine }

struct Ctl: Identifiable {
    let id: String, name: String
    let unit: Int32, sel: Int32, len: Int32, bit: Int32
    let kind: Kind
    var autoId: String? = nil   // automatic mode that drives this value while it is on
}

let allControls: [Ctl] = [
    Ctl(id: "focusAuto", name: "Autofocus", unit: 0, sel: 0x08, len: 1, bit: 17, kind: .auto),
    Ctl(id: "focus", name: "Focus", unit: 0, sel: 0x06, len: 2, bit: 5, kind: .slider, autoId: "focusAuto"),
    Ctl(id: "zoom", name: "Zoom", unit: 0, sel: 0x0B, len: 2, bit: 9, kind: .slider),
    Ctl(id: "aeMode", name: "Auto exposure", unit: 0, sel: 0x02, len: 1, bit: 1, kind: .auto),
    Ctl(id: "exposure", name: "Exposure", unit: 0, sel: 0x04, len: 4, bit: 3, kind: .slider, autoId: "aeMode"),
    Ctl(id: "gain", name: "Gain", unit: 1, sel: 0x04, len: 2, bit: 9, kind: .slider),
    Ctl(id: "backlight", name: "Backlight compensation", unit: 1, sel: 0x01, len: 2, bit: 8, kind: .slider),
    Ctl(id: "wbAuto", name: "Auto white balance", unit: 1, sel: 0x0B, len: 1, bit: 12, kind: .auto),
    Ctl(id: "wb", name: "Color temperature", unit: 1, sel: 0x0A, len: 2, bit: 6, kind: .slider, autoId: "wbAuto"),
    Ctl(id: "brightness", name: "Brightness", unit: 1, sel: 0x02, len: 2, bit: 0, kind: .slider),
    Ctl(id: "contrast", name: "Contrast", unit: 1, sel: 0x03, len: 2, bit: 1, kind: .slider),
    Ctl(id: "saturation", name: "Saturation", unit: 1, sel: 0x07, len: 2, bit: 3, kind: .slider),
    Ctl(id: "hue", name: "Hue", unit: 1, sel: 0x06, len: 2, bit: 2, kind: .slider),
    Ctl(id: "gamma", name: "Gamma", unit: 1, sel: 0x09, len: 2, bit: 5, kind: .slider),
    Ctl(id: "sharpness", name: "Sharpness", unit: 1, sel: 0x08, len: 2, bit: 4, kind: .slider),
    Ctl(id: "powerLine", name: "Anti-flicker", unit: 1, sel: 0x05, len: 1, bit: 10, kind: .powerLine),
]

let sections: [(String, [String])] = [
    ("Focus & zoom", ["focusAuto", "focus", "zoom"]),
    ("Exposure", ["aeMode", "exposure", "gain", "backlight", "powerLine"]),
    ("Color & image", ["wbAuto", "wb", "brightness", "contrast", "saturation", "hue", "gamma", "sharpness"]),
]

struct Range { var min = 0.0, max = 1.0, step = 1.0, def = 0.0 }

@MainActor final class Camera: ObservableObject {
    @Published var connected = false
    @Published var name = ""
    @Published var values: [String: Double] = [:]
    @Published var ranges: [String: Range] = [:]
    var vid = 0, pid = 0
    private var aeAutoValue = 8.0
    private var timer: Timer?
    private let store = UserDefaults.standard

    func ctl(_ id: String) -> Ctl { allControls.first { $0.id == id }! }
    private func key(_ id: String) -> String { "\(vid):\(pid):\(id)" }

    private func read(_ c: Ctl, _ r: Int) -> Double? {
        var v = 0
        return uvc_get(c.unit, c.sel, Int32(r), c.len, &v) == 0 ? Double(v) : nil
    }

    func connect() {
        values = [:]
        ranges = [:]
        connected = uvc_open() != 0
        guard connected else { name = L("No UVC webcam found"); return }
        name = String(cString: uvc_name())
        vid = Int(uvc_vid())
        pid = Int(uvc_pid())
        for c in allControls where uvc_supported(c.unit, c.bit) != 0 {
            var r = Range(def: read(c, UVC_GET_DEF) ?? 0)
            if c.kind == .slider {
                guard let mn = read(c, UVC_GET_MIN), let mx = read(c, UVC_GET_MAX), mx > mn else { continue }
                r = Range(min: mn, max: mx, step: max(read(c, UVC_GET_RES) ?? 1, 1), def: r.def)
            } else if c.id == "aeMode" {
                // GET_RES returns the bitmap of supported modes: 8 = aperture priority, 2 = auto
                let modes = Int(read(c, UVC_GET_RES) ?? 0)
                aeAutoValue = modes & 8 != 0 || modes == 0 ? 8 : 2
            }
            ranges[c.id] = r
            values[c.id] = read(c, UVC_GET_CUR) ?? r.def
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    // While an automatic mode is on, show the value the webcam is choosing.
    private func poll() {
        for c in allControls {
            guard let a = c.autoId, isOn(a), values[c.id] != nil, let v = read(c, UVC_GET_CUR) else { continue }
            values[c.id] = v
        }
    }

    func isOn(_ id: String) -> Bool {
        guard let v = values[id] else { return false }
        return id == "aeMode" ? v != 1 : v != 0
    }

    func set(_ id: String, _ v: Double, save: Bool = true) {
        let c = ctl(id)
        var val = v
        if let r = ranges[id], c.kind == .slider { val = r.min + ((v - r.min) / r.step).rounded() * r.step }
        values[id] = val
        uvc_set(c.unit, c.sel, c.len, Int(val))
        if save { store.set(val, forKey: key(id)) }
    }

    func setAuto(_ id: String, _ on: Bool) {
        let c = ctl(id)
        // some webcams only accept manual focus after an on → off cycle
        if id == "focusAuto" && !on { uvc_set(c.unit, c.sel, 1, 1) }
        set(id, id == "aeMode" ? (on ? aeAutoValue : 1) : (on ? 1 : 0))
        // when turning the automatic mode off, lock the value it had reached
        if !on, let dep = allControls.first(where: { $0.autoId == id }), let cur = read(dep, UVC_GET_CUR) {
            set(dep.id, cur)
        }
    }

    func applySaved() {
        for c in allControls where c.kind != .slider && values[c.id] != nil {
            guard let v = store.object(forKey: key(c.id)) as? Double else { continue }
            if c.kind == .auto { setAuto(c.id, c.id == "aeMode" ? v != 1 : v != 0) } else { set(c.id, v) }
        }
        for c in allControls where c.kind == .slider && values[c.id] != nil && !(c.autoId.map(isOn) ?? false) {
            if let v = store.object(forKey: key(c.id)) as? Double { set(c.id, v) }
        }
    }

    func resetDefaults() {
        for c in allControls where c.kind != .slider { if let r = ranges[c.id] { set(c.id, r.def, save: false) } }
        for c in allControls where c.kind == .slider && !(c.autoId.map(isOn) ?? false) {
            if let r = ranges[c.id] { set(c.id, r.def, save: false) }
        }
        allControls.forEach { store.removeObject(forKey: key($0.id)) }
    }
}

// MARK: - Preview

final class Preview: ObservableObject {
    let session = AVCaptureSession()
    @Published var status = L("Starting preview…")

    func start(vid: Int, pid: Int) {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            DispatchQueue.main.async {
                if ok { self.configure(vid, pid) }
                else { self.status = L("Camera access denied.\nEnable it in System Settings › Privacy & Security › Camera.") }
            }
        }
    }

    private func configure(_ vid: Int, _ pid: Int) {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
        let tag = "VendorID_\(vid) ProductID_\(pid)"
        guard let d = devices.first(where: { $0.modelID.contains(tag) }) ?? devices.first,
              let input = try? AVCaptureDeviceInput(device: d) else { status = L("Preview unavailable"); return }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        status = ""
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }
}

struct PreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        v.layer = layer
        v.wantsLayer = true
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Interface

struct ContentView: View {
    @StateObject private var cam = Camera()
    @StateObject private var preview = Preview()

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.black
                PreviewView(session: preview.session)
                if !preview.status.isEmpty {
                    Text(preview.status).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding()
                }
            }
            .frame(minWidth: 520, minHeight: 360)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                if cam.connected { controls } else { Spacer() }
            }
            .frame(width: 380)
        }
        .onAppear(perform: start)
    }

    private func start() {
        cam.connect()
        guard cam.connected else { preview.status = L("Connect the webcam and press Reconnect"); return }
        preview.start(vid: cam.vid, pid: cam.pid)
        // settings are only accepted while the video is streaming
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { cam.applySaved() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "web.camera")
                Text(cam.name).font(.headline).lineLimit(1)
                Spacer()
                Button(L("Reconnect"), action: start)
            }
            HStack {
                Button(L("Reapply saved")) { cam.applySaved() }
                Button(L("Restore defaults")) { cam.resetDefaults() }
            }
            .disabled(!cam.connected)
            .controlSize(.small)
        }
        .padding(12)
    }

    private var controls: some View {
        Form {
            ForEach(sections, id: \.0) { title, ids in
                let cs = ids.compactMap { id in cam.ranges[id] != nil ? cam.ctl(id) : nil }
                if !cs.isEmpty {
                    Section {
                        ForEach(cs) { row($0) }
                    } header: {
                        Text(L(title))
                    } footer: {
                        if ids.contains("focusAuto") && cam.ranges["focusAuto"] != nil {
                            Text(L("Let the camera focus automatically, then turn autofocus off: focus stays locked at that point."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func row(_ c: Ctl) -> some View {
        switch c.kind {
        case .auto:
            Toggle(L(c.name), isOn: Binding(get: { cam.isOn(c.id) }, set: { cam.setAuto(c.id, $0) }))
        case .powerLine:
            Picker(L(c.name), selection: Binding(get: { Int(cam.values[c.id] ?? 0) }, set: { cam.set(c.id, Double($0)) })) {
                Text(L("Off")).tag(0)
                Text(L("50 Hz (Europe)")).tag(1)
                Text(L("60 Hz (Americas)")).tag(2)
            }
        case .slider:
            let r = cam.ranges[c.id] ?? Range()
            let locked = c.autoId.map(cam.isOn) ?? false
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L(c.name))
                    Spacer()
                    Text("\(Int(cam.values[c.id] ?? r.def))").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { cam.values[c.id] ?? r.def }, set: { cam.set(c.id, $0) }), in: r.min...r.max)
                    .disabled(locked)
            }
            .contextMenu { Button(String(format: L("Default value (%d)"), Int(r.def))) { cam.set(c.id, r.def) } }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct WebcamSettingsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup(L("Webcam Settings")) { ContentView() }
            .windowResizability(.contentMinSize)
    }
}
