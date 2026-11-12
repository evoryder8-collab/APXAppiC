import CoreMotion
import SceneKit
import SwiftUI

/// A glass vessel holding real liquid: the figure holds today's drinks, the capsule holds today's supplements.
/// The liquid stays level while the vessel turns, leans with the wrist and sloshes when something lands in it.
struct WatchVessel: View {
    let shape: WatchVesselShape
    let progress: Double
    /// Colours from the bottom of the liquid (0) to its surface (1).
    let bands: [WatchVesselBand]
    let animates: Bool
    let motionScale: Double

    @StateObject private var renderer: WatchVesselRenderer

    init(shape: WatchVesselShape, progress: Double, bands: [WatchVesselBand], animates: Bool, motionScale: Double) {
        self.shape = shape
        self.progress = progress
        self.bands = bands
        self.animates = animates
        self.motionScale = motionScale
        _renderer = StateObject(wrappedValue: WatchVesselRenderer(shape: shape))
    }

    var body: some View {
        GeometryReader { proxy in
            // SceneView draws one pixel per point on the Watch; drawing it double size and halving it keeps edges crisp.
            SceneView(
                scene: renderer.scene,
                pointOfView: renderer.cameraNode,
                options: animates ? [.rendersContinuously] : [],
                preferredFramesPerSecond: 30,
                antialiasingMode: .multisampling2X,
                delegate: renderer
            )
            .frame(width: proxy.size.width * 2, height: proxy.size.height * 2)
            .scaleEffect(0.5, anchor: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .onAppear {
            renderer.setBands(bands)
            renderer.setProgress(progress, motionScale: liveScale, settle: true)
            if animates { renderer.startMotion() }
        }
        .onChange(of: progress) { _, value in
            renderer.setProgress(value, motionScale: liveScale, settle: !animates)
        }
        .onChange(of: bands) { _, value in renderer.setBands(value) }
        .onChange(of: animates) { _, value in
            renderer.setProgress(progress, motionScale: liveScale, settle: !value)
            if value { renderer.startMotion() } else { renderer.stopMotion() }
        }
        .onDisappear { renderer.stopMotion() }
        .accessibilityHidden(true)
    }

    private var liveScale: Double { animates ? motionScale : 0 }
}

enum WatchVesselShape: Sendable {
    case figure
    case capsule
}

struct WatchVesselBand: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    /// 0 at the bottom of the liquid, 1 at its surface.
    let location: Double
}

/// Owns the scene. SceneKit calls the delegate on its render thread, so shared values sit behind a lock.
final class WatchVesselRenderer: NSObject, ObservableObject, SCNSceneRendererDelegate, @unchecked Sendable {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let shape: WatchVesselShape
    private let vessel = SCNNode()
    private let liquidMaterials: [SCNMaterial]
    private let glowMaterial: SCNMaterial
    private var droplets: [SCNNode] = []
    private let motion = CMMotionManager()
    private let motionQueue = OperationQueue()
    private let lock = NSLock()

    private var target = 0.0
    private var motionScale = 0.0
    private var wristLean = 0.0
    private var pourRequested = false
    private var pulseRequested = false

    private var fill = 0.0
    private var fillVelocity = 0.0
    private var slosh = 0.0
    private var sloshVelocity = 0.0
    private var pulse = 0.0
    private var pourStart: TimeInterval?
    private var lastTime: TimeInterval?

    init(shape: WatchVesselShape) {
        self.shape = shape
        let surface = Self.makeMaterial(Self.liquidShader, cull: .front)
        let body = Self.makeMaterial(Self.liquidShader, cull: .back)
        surface.setValue(1.0, forKey: "isSurface")
        body.setValue(0.0, forKey: "isSurface")
        liquidMaterials = [surface, body]
        glowMaterial = Self.makeMaterial(Self.glowShader, cull: .back, additive: true)
        super.init()
        buildScene()
        apply(fill: 0, slosh: 0, wave: 0, turn: 0, pulse: 0)
    }

    func setProgress(_ progress: Double, motionScale: Double, settle: Bool) {
        let clamped = min(1, max(0, progress.isFinite ? progress : 0))
        lock.lock()
        let rose = clamped > target + 0.0005
        let reachedGoal = clamped >= 1 && target < 1
        target = clamped
        self.motionScale = motionScale
        if settle {
            fill = clamped
            fillVelocity = 0
            slosh = 0
            sloshVelocity = 0
            pulse = 0
        } else {
            pourRequested = pourRequested || rose
            pulseRequested = pulseRequested || reachedGoal
        }
        lock.unlock()
        if settle { apply(fill: clamped, slosh: 0, wave: 0, turn: 0, pulse: 0) }
    }

    func setBands(_ bands: [WatchVesselBand]) {
        guard let image = Self.bandImage(bands) else { return }
        let property = SCNMaterialProperty(contents: image)
        property.wrapS = .clamp
        property.wrapT = .clamp
        for material in liquidMaterials { material.setValue(property, forKey: "bands") }
    }

    func startMotion() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 1.0 / 20.0
        motion.startAccelerometerUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.lock.lock()
            self.wristLean = min(0.6, max(-0.6, data.acceleration.x))
            self.lock.unlock()
        }
    }

    func stopMotion() {
        motion.stopAccelerometerUpdates()
        lock.lock()
        wristLean = 0
        lock.unlock()
    }

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock()
        let step = min(1.0 / 20.0, max(0, time - (lastTime ?? time)))
        lastTime = time
        let scale = motionScale
        guard scale > 0 else {
            lock.unlock()
            return
        }
        if pourRequested {
            pourRequested = false
            pourStart = time
        }
        if pulseRequested {
            pulseRequested = false
            pulse = 1
        }
        // A lightly damped spring: the level overshoots a touch when something lands, then settles.
        fillVelocity += ((target - fill) * 70 - fillVelocity * 9) * step
        fill += fillVelocity * step
        // The surface leans against the wrist and is kicked by a rising level.
        let lean = -wristLean * 0.5 * scale
        sloshVelocity += ((lean - slosh) * 90 - sloshVelocity * 5) * step
        sloshVelocity += fillVelocity * 3.2 * step * (slosh >= 0 ? 1 : -1)
        slosh += sloshVelocity * step
        pulse = max(0, pulse - pulse * 1.6 * step)
        let wave = (0.0035 + min(0.02, abs(fillVelocity) * 0.06)) * scale
        let turn = (sin(time * 0.6) * 0.62 + wristLean * 0.5) * scale
        let pourAge = pourStart.map { time - $0 }
        if let pourAge, pourAge > 1.2 { pourStart = nil }
        let values = (fill, slosh, wave, turn, pulse)
        lock.unlock()
        apply(fill: values.0, slosh: values.1, wave: values.2, turn: values.3, pulse: values.4)
        moveDroplets(age: pourAge, fill: values.0)
    }

    private func apply(fill: Double, slosh: Double, wave: Double, turn: Double, pulse: Double) {
        let range = shape.liquidRange
        // Past the top at a full vessel, so ripples never cut the liquid short of the glass.
        let level = range.lowerBound + (range.upperBound - range.lowerBound) * fill + (fill >= 0.999 ? 0.08 : 0)
        for material in liquidMaterials {
            material.setValue(level, forKey: "level")
            material.setValue(range.lowerBound, forKey: "floor")
            material.setValue(fill > 0.002 ? 1.0 : 0.0, forKey: "holdsLiquid")
            material.setValue(slosh, forKey: "slosh")
            material.setValue(wave, forKey: "wave")
            material.setValue(pulse, forKey: "pulse")
        }
        glowMaterial.setValue(pulse, forKey: "pulse")
        switch shape {
        case .figure: vessel.eulerAngles.y = Float(turn)
        case .capsule: vessel.eulerAngles.z = Float(Self.capsuleLean + turn * 0.45)
        }
    }

    /// Five drops fall through the figure into the liquid when a drink is added.
    private func moveDroplets(age: Double?, fill: Double) {
        guard !droplets.isEmpty else { return }
        // Below the hips the figure is two separate legs, so drops end where the torso does.
        let landing = max(fill, 0.5)
        for (index, droplet) in droplets.enumerated() {
            let local = (age ?? -1) - Double(index) * 0.08
            guard local >= 0, local <= 0.42 else {
                droplet.isHidden = true
                continue
            }
            let travel = (local / 0.42) * (local / 0.42)
            droplet.isHidden = false
            droplet.position = SCNVector3(
                Float(index % 2 == 0 ? -0.012 : 0.012), Float(1.02 - (1.02 - landing) * travel), 0
            )
        }
    }

    // MARK: Scene

    private static let capsuleLean = 0.55

    private func buildScene() {
        scene.background.contents = UIColor.black

        let camera = SCNCamera()
        camera.fieldOfView = 22
        camera.zNear = 0.1
        camera.zFar = 20
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.5, 2.9)
        scene.rootNode.addChildNode(cameraNode)

        let glow = SCNPlane(width: 1.5, height: 1.5)
        glowMaterial.setValue(shape.glowTop, forKey: "top")
        glowMaterial.setValue(shape.glowBottom, forKey: "bottom")
        // The figure sits in a narrow column, so its glow is narrowed to fade out before the column's edge.
        glowMaterial.setValue(shape == .figure ? 2.3 : 1.2, forKey: "stretch")
        glow.firstMaterial = glowMaterial
        let glowNode = SCNNode(geometry: glow)
        glowNode.position = SCNVector3(0, 0.5, -0.6)
        glowNode.renderingOrder = -1
        scene.rootNode.addChildNode(glowNode)

        guard let mesh = shape.mesh() else { return }
        let holder = SCNNode()
        for (order, material) in liquidMaterials.enumerated() {
            let geometry = mesh.copy() as! SCNGeometry
            geometry.firstMaterial = material
            let node = SCNNode(geometry: geometry)
            node.renderingOrder = order
            holder.addChildNode(node)
        }
        let glass = mesh.copy() as! SCNGeometry
        let glassMaterial = Self.makeMaterial(Self.glassShader, cull: .back, additive: true)
        glassMaterial.setValue(shape.glassTop, forKey: "top")
        glassMaterial.setValue(shape.glassBottom, forKey: "bottom")
        glass.firstMaterial = glassMaterial
        let glassNode = SCNNode(geometry: glass)
        glassNode.renderingOrder = 10
        holder.addChildNode(glassNode)
        vessel.addChildNode(holder)
        if shape == .capsule {
            // The capsule turns about its own middle; the figure about its feet.
            vessel.position = SCNVector3(0, 0.5, 0)
        }
        scene.rootNode.addChildNode(vessel)

        guard shape == .figure else { return }
        for _ in 0 ..< 5 {
            let sphere = SCNSphere(radius: 0.011)
            sphere.segmentCount = 10
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = UIColor(red: 0.75, green: 0.96, blue: 1, alpha: 1)
            material.blendMode = .add
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            sphere.firstMaterial = material
            let node = SCNNode(geometry: sphere)
            node.isHidden = true
            node.renderingOrder = 11
            droplets.append(node)
            scene.rootNode.addChildNode(node)
        }
    }

    private static func makeMaterial(_ shader: String, cull: SCNCullMode, additive: Bool = false) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.cullMode = cull
        material.shaderModifiers = [.fragment: shader]
        if additive {
            material.blendMode = .add
            material.writesToDepthBuffer = false
            material.readsFromDepthBuffer = false
        }
        return material
    }

    /// A one-pixel-wide strip, bottom of the liquid at the bottom, that the liquid shader reads its colour from.
    private static func bandImage(_ bands: [WatchVesselBand]) -> CGImage? {
        let height = 64
        let sorted = bands.sorted { $0.location < $1.location }
        guard let first = sorted.first, let last = sorted.last,
              let context = CGContext(
                  data: nil, width: 1, height: height, bitsPerComponent: 8, bytesPerRow: 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        for row in 0 ..< height {
            let location = Double(row) / Double(height - 1)
            let upper = sorted.first { $0.location >= location } ?? last
            let lower = sorted.last { $0.location <= location } ?? first
            let span = upper.location - lower.location
            let mix = span > 0 ? (location - lower.location) / span : 0
            context.setFillColor(
                red: lower.red + (upper.red - lower.red) * mix,
                green: lower.green + (upper.green - lower.green) * mix,
                blue: lower.blue + (upper.blue - lower.blue) * mix,
                alpha: 1
            )
            // CGContext rows count from the bottom, so row 0 is the bottom of the liquid.
            context.fill(CGRect(x: 0, y: row, width: 1, height: 1))
        }
        return context.makeImage()
    }

    // MARK: Shaders

    private static let liquidShader = """
    #pragma arguments
    float level;
    float floor;
    float holdsLiquid;
    float slosh;
    float wave;
    float pulse;
    float isSurface;
    texture2d<float> bands;
    #pragma body
    float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float t = scn_frame.time;
    float ripple = (sin(wp.x * 17.0 + t * 2.3) + sin(wp.z * 13.0 - t * 1.7)) * wave;
    float cut = level + ripple + wp.x * slosh;
    if (wp.y > cut || holdsLiquid < 0.5) { discard_fragment(); }
    float h = clamp((wp.y - floor) / max(cut - floor, 0.001), 0.0, 1.0);
    constexpr sampler bandSampler(filter::linear, address::clamp_to_edge);
    float3 base = bands.sample(bandSampler, float2(0.5, 1.0 - h)).rgb;
    float3 n = normalize(_surface.normal);
    float3 v = normalize(_surface.view);
    float facing = abs(dot(n, v));
    float3 c;
    if (isSurface > 0.5) {
        // The far wall seen through the cut reads as the liquid's surface.
        c = mix(base, float3(1.0), 0.45) * (0.84 + 0.16 * sin(wp.x * 23.0 + t * 1.9));
    } else {
        float rim = pow(1.0 - facing, 2.0);
        c = base * mix(0.45, 1.0, h) * (0.42 + 0.58 * facing);
        c += rim * mix(base, float3(1.0), 0.5) * 0.8;
        c += pow(max(dot(n, normalize(float3(-0.45, 0.7, 0.55))), 0.0), 18.0) * 0.35;
        c += smoothstep(cut - 0.03, cut, wp.y) * mix(base, float3(1.0), 0.75) * 0.5;
    }
    _output.color = float4(c * (1.0 + pulse * 0.6), 1.0);
    """

    private static let glassShader = """
    #pragma arguments
    float3 top;
    float3 bottom;
    #pragma body
    float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float3 n = normalize(_surface.normal);
    float3 v = normalize(_surface.view);
    float rim = pow(1.0 - abs(dot(n, v)), 2.4);
    float3 tint = mix(bottom, top, clamp(wp.y, 0.0, 1.0));
    float spec = pow(max(dot(n, normalize(float3(-0.45, 0.75, 0.5))), 0.0), 28.0);
    float3 c = tint * (0.03 + rim * 0.95) + float3(1.0) * spec * 0.5;
    _output.color = float4(c, 1.0);
    """

    private static let glowShader = """
    #pragma arguments
    float3 top;
    float3 bottom;
    float pulse;
    float stretch;
    #pragma body
    float2 p = _surface.diffuseTexcoord - float2(0.5, 0.5);
    float d = length(p * float2(stretch, 1.0)) * 2.0;
    float falloff = pow(clamp(1.0 - d, 0.0, 1.0), 2.6);
    float3 c = mix(bottom, top, clamp(0.5 - p.y, 0.0, 1.0));
    _output.color = float4(c * falloff * (0.3 + pulse * 0.7), 1.0);
    """
}

private extension WatchVesselShape {
    /// World height of the empty and the full vessel.
    var liquidRange: ClosedRange<Double> {
        switch self {
        case .figure: 0 ... 1
        case .capsule: 0.1 ... 0.9
        }
    }

    var glowTop: SCNVector3 {
        switch self {
        case .figure: SCNVector3(0.3, 0.88, 1.0)
        case .capsule: SCNVector3(1.0, 0.82, 0.35)
        }
    }

    var glowBottom: SCNVector3 {
        switch self {
        case .figure: SCNVector3(0.55, 0.34, 0.98)
        case .capsule: SCNVector3(1.0, 0.42, 0.2)
        }
    }

    var glassTop: SCNVector3 {
        switch self {
        case .figure: glowTop
        case .capsule: SCNVector3(1.0, 0.95, 0.85)
        }
    }

    var glassBottom: SCNVector3 {
        switch self {
        case .figure: glowBottom
        case .capsule: SCNVector3(1.0, 0.72, 0.45)
        }
    }

    func mesh() -> SCNGeometry? {
        switch self {
        case .figure:
            return Self.figureMesh()
        case .capsule:
            let capsule = SCNCapsule(capRadius: 0.2, height: 0.86)
            capsule.radialSegmentCount = 36
            capsule.capSegmentCount = 16
            return capsule
        }
    }

    /// `WatchBody.bin`: vertex count, triangle count, then position + normal per vertex and 16-bit indices.
    /// The mesh is the app's own body silhouette given depth, feet at 0 and head at 1.
    private static func figureMesh() -> SCNGeometry? {
        guard let url = Bundle.main.url(forResource: "WatchBody", withExtension: "bin"),
              let data = try? Data(contentsOf: url), data.count >= 8 else { return nil }
        let vertexCount = Int(data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        let triangleCount = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) })
        let stride = 24
        let vertexBytes = vertexCount * stride
        guard data.count == 8 + vertexBytes + triangleCount * 6 else { return nil }
        let vertices = data.subdata(in: 8 ..< 8 + vertexBytes)
        let indices = data.subdata(in: 8 + vertexBytes ..< data.count)
        func source(_ semantic: SCNGeometrySource.Semantic, offset: Int, components: Int = 3) -> SCNGeometrySource {
            SCNGeometrySource(
                data: vertices, semantic: semantic, vectorCount: vertexCount, usesFloatComponents: true,
                componentsPerVector: components, bytesPerComponent: 4, dataOffset: offset, dataStride: stride
            )
        }
        // SceneKit insists on texture coordinates once a material samples a texture; the shader never reads them.
        let unusedCoordinates = source(.texcoord, offset: 0, components: 2)
        let element = SCNGeometryElement(
            data: indices, primitiveType: .triangles, primitiveCount: triangleCount, bytesPerIndex: 2
        )
        return SCNGeometry(
            sources: [source(.vertex, offset: 0), source(.normal, offset: 12), unusedCoordinates], elements: [element]
        )
    }
}
