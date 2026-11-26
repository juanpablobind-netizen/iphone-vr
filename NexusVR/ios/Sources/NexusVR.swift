import SwiftUI
import UIKit
import ARKit
import Vision
import CoreImage
import simd

struct Hand: Codable, Identifiable {
    var side: String; var pos: [Float]; var rot: [Float]; var points: [[Float]?]
    var pinch: Bool; var grab: Bool; var menu: Bool
    var id: String { side }
}
struct Packet: Codable { var head: [Float]; var hands: [Hand]; var tracking: Bool }

final class Tracker: NSObject, ObservableObject, ARSessionDelegate {
    @Published var status = "Sin conectar"
    @Published var hands: [Hand] = []
    @Published var camera: UIImage?
    @Published var screen: UIImage?
    @Published var running = false
    let session = ARSession()
    private let queue = DispatchQueue(label: "nexus.tracker")
    private let context = CIContext()
    private let vision = VNDetectHumanHandPoseRequest()
    private let network: URLSession = { let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 1.5; c.timeoutIntervalForResource = 3; return URLSession(configuration: c) }()
    private var base: URL?, key = "", busy = false, last: TimeInterval = 0, generation = 0
    private var center: simd_float4x4?, previous: [String: Hand] = [:]
    private var previewTask: Task<Void,Never>?
    static let joints: [VNHumanHandPoseObservation.JointName] = [.wrist,.thumbCMC,.thumbMP,.thumbIP,.thumbTip,.indexMCP,.indexPIP,.indexDIP,.indexTip,.middleMCP,.middlePIP,.middleDIP,.middleTip,.ringMCP,.ringPIP,.ringDIP,.ringTip,.littleMCP,.littlePIP,.littleDIP,.littleTip]
    override init() { super.init(); session.delegate = self; session.delegateQueue = queue; vision.maximumHandCount = 2 }
    func start(_ address: String, _ code: String) {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "http", url.host != nil, url.port != nil, !code.isEmpty else { status = "Dirección o clave inválida"; return }
        guard ARWorldTrackingConfiguration.isSupported else { status = "ARKit no disponible"; return }
        stop(); running = true; status = "Conectando…"
        queue.async { self.generation += 1; self.base = url; self.key = code; self.center = nil; self.last = 0; self.previous = [:]; self.busy = false }
        let config = ARWorldTrackingConfiguration(); config.worldAlignment = .gravity; session.run(config, options: [.resetTracking,.removeExistingAnchors])
        UIApplication.shared.isIdleTimerDisabled = true
    }
    func stop() {
        running = false; status = "Sin conectar"; hands = []; camera = nil; stopPreview(); session.pause(); UIApplication.shared.isIdleTimerDisabled = false
        queue.async { self.generation += 1; self.base = nil; self.busy = false; self.previous = [:] }
    }
    func recenter() { queue.async { self.center = nil; self.previous = [:] } }
    func session(_ session: ARSession, didFailWithError error: Error) { DispatchQueue.main.async { self.status = error.localizedDescription; self.running = false } }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let url = base, frame.timestamp-last >= 1.0/25 else { return }; last = frame.timestamp
        let normal: Bool; if case .normal = frame.camera.trackingState { normal = true } else { normal = false }
        if center == nil && normal { center = simd_inverse(frame.camera.transform) }
        let m = (center ?? matrix_identity_float4x4) * frame.camera.transform
        let q = simd_quatf(m).vector
        var found: [Hand] = []
        do {
            try VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .up, options: [:]).perform([vision])
            for observation in vision.results ?? [] {
                if let h = read(observation, frame.camera) { found.append(h) }
            }
        } catch { found = [] }
        var bySide: [String:Hand] = [:]; for h in found { bySide[h.side] = h }; found = Array(bySide.values); previous = bySide
        let ci = CIImage(cvPixelBuffer: frame.capturedImage)
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: 0.40, y: 0.40))
        let image = context.createCGImage(scaled, from: scaled.extent).map { UIImage(cgImage: $0) }
        let displayed = found
        DispatchQueue.main.async { if self.running { self.hands = displayed; self.camera = image } }
        guard !busy else { return }; busy = true; let current = generation
        let packet = Packet(head: [m.columns.3.x,m.columns.3.y,m.columns.3.z,q.x,q.y,q.z,q.w], hands: found, tracking: normal)
        var req = URLRequest(url: url.appendingPathComponent("pose")); req.httpMethod = "POST"; req.setValue(key, forHTTPHeaderField: "X-Nexus-Key"); req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try? JSONEncoder().encode(packet)
        network.dataTask(with: req) { _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode
            self.queue.async {
                guard current == self.generation else { return }; self.busy = false
                DispatchQueue.main.async { if self.running { self.status = error != nil ? "Sin respuesta del PC" : code == 200 ? (normal ? "Conectado · AR activo" : "Conectado · calibrando AR") : "Error HTTP \(code ?? 0)" } }
            }
        }.resume()
    }
    private func read(_ obs: VNHumanHandPoseObservation,_ cam: ARCamera) -> Hand? {
        let points = Self.joints.map { joint -> [Float]? in
            guard let p = try? obs.recognizedPoint(joint), p.confidence >= 0.45 else { return nil }
            return [Float(p.location.x),Float(p.location.y)]
        }
        func v(_ i: Int) -> SIMD2<Float>? { guard let p = points[i] else { return nil }; return SIMD2(p[0],p[1]) }
        guard let wrist = v(0), let a = v(5), let b = v(17), let middle = v(9), let thumb = v(4), let index = v(8) else { return nil }
        let side: String
        switch obs.chirality { case .left: side = "left"; case .right: side = "right"; default: return nil }
        let w = Float(cam.imageResolution.width), h = Float(cam.imageResolution.height)
        func px(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2(p.x*w,(1-p.y)*h) }
        let palm = simd_length(px(a)-px(b)); guard palm > 12 else { return nil }
        let depth = min(1.5,max(0.15,cam.intrinsics.columns.0.x*0.075/palm))
        let pivot = px((wrist+middle)*0.5)
        let pos = SIMD3((pivot.x-cam.intrinsics.columns.2.x)*depth/cam.intrinsics.columns.0.x, -(pivot.y-cam.intrinsics.columns.2.y)*depth/cam.intrinsics.columns.1.y, -depth)
        let axis = px(middle)-px(wrist); let angle = atan2(-axis.x,-axis.y)
        let quat = simd_quatf(angle: angle, axis: SIMD3<Float>(0,0,1)).vector
        let old = previous[side]
        let pinch = simd_length(px(thumb)-px(index))/palm < ((old?.pinch ?? false) ? 0.42 : 0.29)
        let distances = [12,16,20].compactMap { i -> Float? in guard let p = v(i) else { return nil }; return simd_length(px(p)-px(wrist))/palm }
        let grab = distances.count == 3 && distances.allSatisfy { $0 < ((old?.grab ?? false) ? 1.48 : 1.22) }
        let menu = !pinch && !grab && (v(12).map { simd_length(px(thumb)-px($0))/palm < ((old?.menu ?? false) ? 0.42 : 0.27) } ?? false)
        let smooth = old.map { old in SIMD3<Float>(old.pos[0],old.pos[1],old.pos[2])*0.55+pos*0.45 } ?? pos
        return Hand(side: side,pos:[smooth.x,smooth.y,smooth.z],rot:[quat.x,quat.y,quat.z,quat.w],points:points,pinch:pinch,grab:grab,menu:menu)
    }
    func stopPreview() { previewTask?.cancel(); previewTask = nil; screen = nil }
    func startPreview(_ address:String,_ code:String) {
        stopPreview(); guard let url = URL(string:address) else { return }
        previewTask = Task { @MainActor in
            while !Task.isCancelled {
                var req = URLRequest(url:url.appendingPathComponent("frame")); req.setValue(code,forHTTPHeaderField:"X-Nexus-Key")
                if let (data,r) = try? await network.data(for:req), (r as? HTTPURLResponse)?.statusCode == 200, !Task.isCancelled { screen = UIImage(data:data) } else if !Task.isCancelled { screen = nil }
                try? await Task.sleep(nanoseconds: 66_000_000)
            }
        }
    }
}

struct Skeleton: View {
    let hands: [Hand]
    let edges = [[0,1,2,3,4],[0,5,6,7,8],[0,9,10,11,12],[0,13,14,15,16],[0,17,18,19,20],[5,9,13,17]]
    var body: some View { Canvas { ctx,size in
        for hand in hands {
            let color: Color = hand.side == "left" ? .cyan : .mint
            func p(_ i:Int)->CGPoint? { guard let v=hand.points[i] else { return nil }; return CGPoint(x:CGFloat(v[0])*size.width,y:(1-CGFloat(v[1]))*size.height) }
            for chain in edges { for (a,b) in zip(chain,chain.dropFirst()) { if let x=p(a),let y=p(b) { var path=Path(); path.move(to:x); path.addLine(to:y);ctx.stroke(path,with:.color(color),lineWidth:3) } } }
            for i in 0..<21 { if let x=p(i) { ctx.fill(Path(ellipseIn:CGRect(x:x.x-3,y:x.y-3,width:6,height:6)),with:.color(color)) } }
        }
    } }
}
struct MainView: View {
    @StateObject private var tracker=Tracker()
    @AppStorage("host") private var host="http://192.168.1.10:8765"
    @State private var key=""
    @State private var mode="Manos"
    @Environment(\.scenePhase) private var phase
    var body: some View {
        HStack(spacing:16) {
            VStack(alignment:.leading,spacing:9) {
                Text("NEXUS VR").font(.system(size:27,weight:.heavy,design:.rounded)).foregroundStyle(.cyan)
                Text("PCVR LAB · 0.1").font(.caption.monospaced()).foregroundStyle(.secondary)
                TextField("http://IP:8765",text:$host).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).disabled(tracker.running)
                SecureField("Clave de sesión",text:$key).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).disabled(tracker.running)
                Button(tracker.running ? "Desconectar" : "Conectar") { if tracker.running { tracker.stop() } else { tracker.start(host,key); if mode != "Manos" { tracker.startPreview(host,key) } } }.buttonStyle(.borderedProminent).tint(.blue)
                Button("Recentrar cabeza") { tracker.recenter() }.buttonStyle(.bordered).disabled(!tracker.running)
                Text(tracker.status).font(.caption).foregroundStyle(.mint)
                Text("Manos: \(tracker.hands.count) · visión monocular").font(.caption2)
                Spacer(minLength:0)
            }.frame(width:230)
            VStack(spacing:6) {
                Picker("Modo",selection:$mode) { Text("Manos").tag("Manos");Text("PC").tag("PC");Text("SBS").tag("SBS") }.pickerStyle(.segmented).onChange(of:mode) { value in if value == "Manos" { tracker.stopPreview() } else if tracker.running { tracker.startPreview(host,key) } }
                GeometryReader { geo in
                    ZStack {
                        RoundedRectangle(cornerRadius:15).fill(.black)
                        if mode == "Manos" {
                            if let im=tracker.camera {
                                let scale=min(geo.size.width/im.size.width,geo.size.height/im.size.height)
                                let w=im.size.width*scale,h=im.size.height*scale
                                ZStack { Image(uiImage:im).resizable();Skeleton(hands:tracker.hands) }.frame(width:w,height:h)
                            } else { Text("Inicia la cámara para ver tus manos").font(.caption) }
                        } else if let im=tracker.screen {
                            if mode == "PC" { Image(uiImage:im).resizable().scaledToFit() }
                            else { HStack(spacing:4) { ForEach(0..<2) { _ in Image(uiImage:im).resizable().scaledToFit() } } }
                        } else { Text("Activa VISTA_PC.bat en Windows").font(.caption) }
                    }.clipShape(RoundedRectangle(cornerRadius:15))
                }
                Text(mode == "SBS" ? "Prueba 2D duplicada · no es VR estereoscópica" : mode == "PC" ? "Vista remota JPEG · sin audio" : "Cámara local · 21 puntos por mano").font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(16).preferredColorScheme(.dark).onChange(of:phase) { p in if p != .active && tracker.running { tracker.stop() } }
    }
}
@main struct NexusApp: App { var body: some Scene { WindowGroup { MainView() } } }
