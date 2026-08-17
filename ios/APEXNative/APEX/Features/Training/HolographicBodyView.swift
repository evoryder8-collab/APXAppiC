import SceneKit
import SwiftUI

struct HolographicBodyView: UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let dayType: String
    let accent: Color

    final class Coordinator {
        var renderKey: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.025, green: 0.035, blue: 0.075, alpha: 1)
        view.scene = buildScene(animate: !reduceMotion)
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.rendersContinuously = !reduceMotion
        context.coordinator.renderKey = renderKey
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard context.coordinator.renderKey != renderKey else { return }
        view.scene = buildScene(animate: !reduceMotion)
        view.rendersContinuously = !reduceMotion
        context.coordinator.renderKey = renderKey
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.rendersContinuously = false
        view.scene = nil
        coordinator.renderKey = nil
    }

    private var renderKey: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(accent).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%@|%.4f|%.4f|%.4f|%.4f|%@", dayType, red, green, blue, alpha, reduceMotion.description)
    }

    private func buildScene(animate: Bool) -> SCNScene {
        let scene = SCNScene()
        let body = SCNNode()
        body.name = "holographic-body"
        scene.rootNode.addChildNode(body)

        let cyan = UIColor(red: 0.12, green: 0.83, blue: 1, alpha: 0.68)
        let highlight = UIColor(accent)
        let active = activeGroups

        addPart(SCNSphere(radius: 0.24), at: .init(0, 2.05, 0), name: "head", active: false, body: body, cyan: cyan, highlight: highlight)
        addPart(SCNCapsule(capRadius: 0.34, height: 1.05), at: .init(0, 1.28, 0), scale: .init(1.0, 1.0, 0.62), name: "torso", active: active.contains("torso"), body: body, cyan: cyan, highlight: highlight)
        addPart(SCNCapsule(capRadius: 0.18, height: 0.48), at: .init(0, 0.63, -0.03), scale: .init(1.45, 1, 0.8), name: "glutes", active: active.contains("glutes"), body: body, cyan: cyan, highlight: highlight)

        for side: Float in [-1, 1] {
            addLimb(body: body, x: side * 0.48, y: 1.48, length: 0.72, radius: 0.11, angle: side * -0.12, name: "shoulders", active: active.contains("upper"), cyan: cyan, highlight: highlight)
            addLimb(body: body, x: side * 0.62, y: 0.93, length: 0.66, radius: 0.09, angle: side * 0.03, name: "arms", active: active.contains("arms"), cyan: cyan, highlight: highlight)
            addLimb(body: body, x: side * 0.22, y: 0.10, length: 0.94, radius: 0.15, angle: side * 0.02, name: "thighs", active: active.contains("legs"), cyan: cyan, highlight: highlight)
            addLimb(body: body, x: side * 0.22, y: -0.77, length: 0.86, radius: 0.105, angle: side * -0.01, name: "calves", active: active.contains("legs"), cyan: cyan, highlight: highlight)
        }

        let ring = SCNTorus(ringRadius: 0.78, pipeRadius: 0.006)
        ring.firstMaterial?.diffuse.contents = highlight.withAlphaComponent(0.45)
        ring.firstMaterial?.emission.contents = highlight.withAlphaComponent(0.8)
        let ringNode = SCNNode(geometry: ring)
        ringNode.eulerAngles.x = .pi / 2
        ringNode.position.y = 0.55
        body.addChildNode(ringNode)

        if animate {
            body.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 15)))
        }

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 46
        camera.position = SCNVector3(0, 0.55, 5.2)
        camera.look(at: SCNVector3(0, 0.55, 0))
        scene.rootNode.addChildNode(camera)

        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .omni
        light.light?.color = UIColor.white
        light.light?.intensity = 480
        light.position = .init(0, 3, 3)
        scene.rootNode.addChildNode(light)

        return scene
    }

    private var activeGroups: Set<String> {
        switch dayType {
        case "legs_a", "legs_b": ["glutes", "legs"]
        case "push": ["torso", "upper", "arms"]
        case "pull": ["torso", "upper", "arms"]
        case "upper": ["torso", "upper", "arms"]
        case "t25": ["torso", "legs"]
        case "mobility", "fix": ["torso"]
        default: ["torso", "legs", "arms"]
        }
    }

    private func addPart(
        _ geometry: SCNGeometry,
        at position: SCNVector3,
        scale: SCNVector3 = .init(1, 1, 1),
        name: String,
        active: Bool,
        body: SCNNode,
        cyan: UIColor,
        highlight: UIColor
    ) {
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.position = position
        node.scale = scale
        style(node.geometry, active: active, cyan: cyan, highlight: highlight)
        body.addChildNode(node)
    }

    private func addLimb(body: SCNNode, x: Float, y: Float, length: CGFloat, radius: CGFloat, angle: Float, name: String, active: Bool, cyan: UIColor, highlight: UIColor) {
        let capsule = SCNCapsule(capRadius: radius, height: length)
        let node = SCNNode(geometry: capsule)
        node.position = .init(x, y, 0)
        node.eulerAngles.z = angle
        node.name = name
        style(capsule, active: active, cyan: cyan, highlight: highlight)
        body.addChildNode(node)
    }

    private func style(_ geometry: SCNGeometry?, active: Bool, cyan: UIColor, highlight: UIColor) {
        let material = SCNMaterial()
        material.diffuse.contents = (active ? highlight : cyan).withAlphaComponent(active ? 0.72 : 0.38)
        material.emission.contents = (active ? highlight : cyan).withAlphaComponent(active ? 0.95 : 0.48)
        material.transparency = active ? 0.86 : 0.62
        material.blendMode = .add
        material.isDoubleSided = true
        geometry?.materials = [material]
    }
}
