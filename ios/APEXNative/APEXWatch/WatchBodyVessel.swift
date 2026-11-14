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
    /// Each change sends drops through the figure; each change of the second plays the goal celebration.
    var pourToken = 0
    var celebrationToken = 0
    /// Turning false fades the rays and sparks out, so a celebration ended by a tap does not play on in the small column.
    var celebrating = false

    @StateObject private var renderer: WatchVesselRenderer

    init(
        shape: WatchVesselShape, progress: Double, bands: [WatchVesselBand], animates: Bool, motionScale: Double,
        pourToken: Int = 0, celebrationToken: Int = 0, celebrating: Bool = false
    ) {
        self.celebrating = celebrating
        self.pourToken = pourToken
        self.celebrationToken = celebrationToken
        self.shape = shape
        self.progress = progress
        self.bands = bands
        self.animates = animates
        self.motionScale = motionScale
        _renderer = StateObject(wrappedValue: WatchVesselRenderer(shape: shape))
    }

    var body: some View {
        // SceneView already draws at the screen's pixel density (a 95 × 193 pt view renders 190 × 386 px on
        // watchOS 27), so it is drawn at its own size; 4× multisampling keeps the glass edges smooth.
        SceneView(
            scene: renderer.scene,
            pointOfView: renderer.cameraNode,
            options: animates ? [.rendersContinuously] : [],
            preferredFramesPerSecond: 30,
            antialiasingMode: .multisampling4X,
            delegate: renderer
        )
        .onAppear {
            renderer.setBands(bands)
            renderer.setProgress(progress, motionScale: liveScale, settle: true)
            if animates { renderer.startMotion() }
        }
        .onChange(of: progress) { _, value in
            renderer.setProgress(value, motionScale: liveScale, settle: !animates)
        }
        .onChange(of: bands) { _, value in renderer.setBands(value) }
        .onChange(of: pourToken) { if animates { renderer.pour() } }
        .onChange(of: celebrationToken) { if animates { renderer.celebrate() } }
        .onChange(of: celebrating) { _, on in if !on { renderer.endCelebration() } }
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
    private var sparks: [SCNNode] = []
    private let motion = CMMotionManager()
    private let motionQueue = OperationQueue()
    private let lock = NSLock()

    private var target = 0.0
    private var motionScale = 0.0
    private var wristLean = 0.0
    private var pourRequested = false
    private var pulseRequested = false
    private var celebrationRequested = false
    private var celebrationEndRequested = false
    /// When the celebration was ended early; its light fades from here while the turn finishes.
    private var celebrationEnd: TimeInterval?

    private var fill = 0.0
    private var fillVelocity = 0.0
    private var slosh = 0.0
    private var sloshVelocity = 0.0
    private var pulse = 0.0
    private var pourStart: TimeInterval?
    private var celebrationStart: TimeInterval?
    /// 1 while the goal is held: the liquid keeps a slow rising shimmer.
    private var charged = 0.0
    private var lastTime: TimeInterval?
    /// How much of the idle sway is applied, and how far the camera has eased in; each moves on a spring.
    private var swayWeight = 1.0
    private var swayVelocity = 0.0
    private var dolly = 0.0
    private var dollyVelocity = 0.0
    /// Whether any spark or drop may be showing; idle frames then leave the hidden nodes alone.
    private var sparksShown = false
    private var dropletsShown = false

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

    func pour() {
        lock.lock()
        pourRequested = true
        lock.unlock()
    }

    func celebrate() {
        lock.lock()
        celebrationRequested = true
        lock.unlock()
    }

    func endCelebration() {
        lock.lock()
        celebrationEndRequested = true
        lock.unlock()
    }

    func setProgress(_ progress: Double, motionScale: Double, settle: Bool) {
        let clamped = min(1, max(0, progress.isFinite ? progress : 0))
        lock.lock()
        // The capsule glows by itself when the last supplement is ticked; the figure is told when to celebrate.
        let reachedGoal = shape == .capsule && clamped >= 1 && target < 1
        target = clamped
        self.motionScale = motionScale
        if settle {
            fill = clamped
            fillVelocity = 0
            slosh = 0
            sloshVelocity = 0
            pulse = 0
            // A pour cut short by a lowered wrist must not hang in mid-air or replay later.
            pourStart = nil
            pourRequested = false
            pulseRequested = false
            celebrationStart = nil
            celebrationRequested = false
            celebrationEndRequested = false
            celebrationEnd = nil
            charged = clamped >= 1 ? 1 : 0
            swayWeight = 1
            swayVelocity = 0
            dolly = 0
            dollyVelocity = 0
            apply(fill: clamped, slosh: 0, wave: 0, turn: 0, pulse: 0)
            for node in droplets + sparks { node.isHidden = true }
            sparksShown = false
            dropletsShown = false
        } else {
            pulseRequested = pulseRequested || reachedGoal
        }
        lock.unlock()
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
        charged += ((target >= 1 ? 1 : 0) - charged) * min(1, step * 2)
        if celebrationRequested {
            celebrationRequested = false
            celebrationEndRequested = false
            celebrationStart = time
            celebrationEnd = nil
        }
        if celebrationEndRequested {
            celebrationEndRequested = false
            if celebrationStart != nil, celebrationEnd == nil { celebrationEnd = time }
        }
        // The goal, in order: the figure stops swaying and winds back, turns once on a spring while a band of
        // light climbs it, flares at the head and throws embers, then rays open behind it as the camera eases in.
        var spin = 0.0
        var sweep = -1.0
        var sweepGlow = 0.0
        var rays = 0.0
        var light = 0.0
        var burstAge: Double?
        if let start = celebrationStart {
            let age = time - start
            // 1 until the celebration is let go early, then eased out to 0.
            light = celebrationEnd.map { 1 - Self.ease((time - $0) / 0.4) } ?? 1
            spin = Self.spin(age)
            if age > Self.celebrationLength || (light <= 0 && age > Self.spinLength) {
                celebrationStart = nil
                celebrationEnd = nil
                spin = 0
                light = 0
            } else if light > 0 {
                sweep = -0.08 + 1.2 * Self.ease(age / Self.burstTime)
                sweepGlow = Self.ease(age / 0.15) * (1 - Self.ease((age - Self.burstTime) / 0.3)) * light
                if age >= Self.burstTime {
                    burstAge = age - Self.burstTime
                    pulse = max(pulse, Self.flash(age - Self.burstTime) * light)
                }
                // Rays open like light through a door: fast at first, then slowly to full.
                let opened = 1 - exp(-max(0, age - Self.burstTime - 0.05) * 5)
                let closing = Self.ease((age - Self.holdEnd) / (Self.celebrationLength - Self.holdEnd))
                rays = opened * (1 - closing) * light
            }
        }
        // Critically damped springs: the sway and the camera move as if weighted, and never overshoot.
        let celebrating = celebrationStart != nil
        Self.spring(&swayWeight, &swayVelocity, toward: celebrating ? 0 : 1, omega: celebrating ? 6 : 2.4, step: step)
        Self.spring(&dolly, &dollyVelocity, toward: light > 0 ? 1 : 0, omega: 3.4, step: step)
        let wave = (0.0035 + min(0.02, abs(fillVelocity) * 0.06)) * scale
        let turn = (sin(time * 0.6) * 0.62 + wristLean * 0.5) * scale * swayWeight + spin
        let pourAge = pourStart.map { time - $0 }
        if let pourAge, pourAge > 1.2 { pourStart = nil }
        // Written under the lock so a settle on the main thread can never be overwritten by a stale frame.
        apply(
            fill: fill, slosh: slosh, wave: wave, turn: turn, pulse: pulse,
            sweep: sweep, sweepGlow: sweepGlow, rays: rays, dolly: dolly
        )
        moveDroplets(age: pourAge, fill: fill)
        moveSparks(age: burstAge, strength: light)
        lock.unlock()
    }

    /// Seconds from the goal to the flare, to the moment the celebration lets go, and to its very end.
    static let burstTime = 0.95
    static let holdEnd = 3.4
    static let celebrationLength = 4.4
    /// The turn is all but finished by then, so the celebration can end without a visible snap.
    private static let spinLength = 2.6

    /// Quintic ease in and out: no jerk at either end. Clamped to 0 ... 1.
    private static func ease(_ value: Double) -> Double {
        let t = min(1, max(0, value))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    /// One full turn: a short wind back, then a critically damped spring to 360°, with no overshoot.
    private static func spin(_ age: Double) -> Double {
        let back = sin(Double.pi * min(1, max(0, age / 0.4)))
        let t = max(0, age - 0.14)
        let omega = 3.6
        return -0.2 * back * back + 2 * Double.pi * (1 - (1 + omega * t) * exp(-omega * t))
    }

    /// The flare: up in 70 ms, then dying away like a struck light.
    private static func flash(_ k: Double) -> Double {
        ease(k / 0.07) * exp(-max(0, k - 0.07) * 1.6)
    }

    private static func spring(
        _ value: inout Double, _ velocity: inout Double, toward target: Double, omega: Double, step: Double
    ) {
        velocity += (omega * omega * (target - value) - 2 * omega * velocity) * step
        value += velocity * step
    }

    private func apply(
        fill: Double, slosh: Double, wave: Double, turn: Double, pulse: Double,
        sweep: Double = -1, sweepGlow: Double = 0, rays: Double = 0, dolly: Double = 0
    ) {
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
            material.setValue(sweep, forKey: "sweep")
            material.setValue(sweepGlow, forKey: "sweepGlow")
            material.setValue(charged, forKey: "charged")
        }
        glowMaterial.setValue(pulse, forKey: "pulse")
        glowMaterial.setValue(rays, forKey: "rays")
        // An empty capsule is clear glass; its warm light comes up with what it holds.
        glowMaterial.setValue(shape == .figure ? 0.3 : 0.06 + 0.34 * fill, forKey: "ambient")
        // The figure's glow is narrowed to its column; the celebration takes the whole screen, so it opens out.
        glowMaterial.setValue(shape.glowStretch + (1 - shape.glowStretch) * rays, forKey: "stretch")
        cameraNode.position.z = Float(2.9 - 0.2 * dolly)
        switch shape {
        case .figure: vessel.eulerAngles.y = Float(turn)
        case .capsule: vessel.eulerAngles.z = Float(Self.capsuleLean + turn * 0.45)
        }
    }

    /// Five drops fall through the figure into the liquid when a drink is added.
    private func moveDroplets(age: Double?, fill: Double) {
        guard !droplets.isEmpty, age != nil || dropletsShown else { return }
        dropletsShown = age != nil
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

    /// Embers leave the whole figure at the flare: thrown out fast, slowed by the air, then drifting down.
    private func moveSparks(age: Double?, strength: Double) {
        guard age != nil || sparksShown else { return }
        sparksShown = age != nil
        let drag = 2.6
        let gravity = 0.55
        for (index, spark) in sparks.enumerated() {
            let seed = Double(index)
            let a = (seed * 0.618).truncatingRemainder(dividingBy: 1)
            let b = (seed * 0.37).truncatingRemainder(dividingBy: 1)
            let c = (seed * 0.77).truncatingRemainder(dividingBy: 1)
            let life = 1.4 + 0.8 * a
            let local = (age ?? -1) - c * 0.12
            guard local >= 0, local <= life else {
                spark.isHidden = true
                continue
            }
            let angle = seed * 2.399963
            let speed = 0.75 + 0.9 * a
            // Linear drag: the distance covered levels off at speed / drag, while gravity keeps a slow fall.
            let reach = (1 - exp(-drag * local)) / drag
            let rise = (sin(angle) * 0.5 + 0.6) * speed
            let left = 1 - local / life
            let twinkle = 0.8 + 0.2 * sin(local * (22 + 9 * a) + seed)
            let size = (0.55 + 0.45 * left) * twinkle
            spark.isHidden = false
            spark.position = SCNVector3(
                Float(cos(angle) * speed * 0.85 * reach),
                Float(0.3 + 0.62 * b + (rise + gravity / drag) * reach - gravity / drag * local),
                0.12
            )
            spark.scale = SCNVector3(Float(size), Float(size), 1)
            spark.opacity = CGFloat(Self.ease(local / 0.06) * pow(left, 1.6) * strength)
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
        glowMaterial.setValue(shape.glowStretch, forKey: "stretch")
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
        // The capsule is a plain round shape, so a tighter edge keeps its middle clear instead of milky.
        glassMaterial.setValue(shape == .figure ? 2.4 : 3.2, forKey: "edge")
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
        let sparkColors = [
            UIColor(red: 1, green: 1, blue: 1, alpha: 1),
            UIColor(red: 0.45, green: 0.93, blue: 1, alpha: 1),
            UIColor(red: 0.72, green: 0.55, blue: 1, alpha: 1),
            UIColor(red: 1, green: 0.86, blue: 0.5, alpha: 1)
        ]
        for index in 0 ..< 46 {
            let sphere = SCNSphere(radius: index % 3 == 0 ? 0.015 : 0.009)
            sphere.segmentCount = 8
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = sparkColors[index % sparkColors.count]
            material.blendMode = .add
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            sphere.firstMaterial = material
            let node = SCNNode(geometry: sphere)
            node.isHidden = true
            node.renderingOrder = 12
            sparks.append(node)
            scene.rootNode.addChildNode(node)
        }
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
    float sweep;
    float sweepGlow;
    float charged;
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
        // Lit from the upper left so the chest, arms and legs keep their roundness when the figure is full.
        float lit = 0.6 + 0.62 * max(dot(n, normalize(float3(-0.5, 0.55, 0.65))), 0.0);
        c = base * mix(0.45, 1.0, h) * (0.42 + 0.58 * facing) * lit;
        c += rim * mix(base, float3(1.0), 0.5) * 0.8;
        c += pow(max(dot(n, normalize(float3(-0.45, 0.7, 0.55))), 0.0), 18.0) * 0.35;
        c += smoothstep(cut - 0.03, cut, wp.y) * mix(base, float3(1.0), 0.75) * 0.5;
        float streak = pow(0.5 + 0.5 * sin(wp.y * 15.0 - t * 2.2 + sin(wp.x * 9.0 + t * 0.6) * 0.8), 5.0);
        c += charged * streak * mix(base, float3(1.0), 0.6) * 0.17;
    }
    float band = wp.y - sweep;
    c += exp(-band * band * 90.0) * float3(1.0, 0.97, 0.9) * 1.2 * sweepGlow;
    _output.color = float4(c * (1.0 + pulse * 0.6), 1.0);
    """

    private static let glassShader = """
    #pragma arguments
    float3 top;
    float3 bottom;
    float edge;
    #pragma body
    float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float3 n = normalize(_surface.normal);
    float3 v = normalize(_surface.view);
    float rim = pow(1.0 - abs(dot(n, v)), edge);
    float3 tint = mix(bottom, top, clamp(wp.y, 0.0, 1.0));
    float spec = pow(max(dot(n, normalize(float3(-0.45, 0.75, 0.5))), 0.0), 28.0);
    float3 c = tint * (0.007 + rim * 0.95) + float3(1.0) * spec * 0.5;
    _output.color = float4(c, 1.0);
    """

    private static let glowShader = """
    #pragma arguments
    float3 top;
    float3 bottom;
    float pulse;
    float stretch;
    float rays;
    float ambient;
    #pragma body
    float2 p = _surface.diffuseTexcoord - float2(0.5, 0.5);
    float d = length(p * float2(stretch, 1.0)) * 2.0;
    float falloff = pow(clamp(1.0 - d, 0.0, 1.0), 2.6);
    float3 c = mix(bottom, top, clamp(0.5 - p.y, 0.0, 1.0));
    float3 light = c * falloff * (ambient + pulse * 0.7 + rays * 0.3);
    // The plane covers the whole view, so the beams are only worked out while the celebration shows them.
    if (rays > 0.0) {
        float angle = atan2(p.y, p.x);
        float beams = pow(abs(sin(angle * 6.0 + scn_frame.time * 0.35)), 8.0)
            + 0.5 * pow(abs(sin(angle * 11.0 - scn_frame.time * 0.22)), 10.0);
        float reach = pow(clamp(1.0 - length(p) * 2.5, 0.0, 1.0), 1.15);
        light += mix(c, float3(1.0), 0.12) * beams * reach * rays * 1.25;
    }
    _output.color = float4(light, 1.0);
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

    var glowStretch: Double { self == .figure ? 2.3 : 1.2 }

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
