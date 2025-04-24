//
//  ViewController.swift
//  lagTestARKIT
//
//  Created by Vishwas Prakash on 21/04/25.
//
import UIKit
import ARKit
import MetalKit
import SceneKit
import FlamMetalKit

class ARTrackingViewController: UIViewController, ARSessionDelegate, ARTrackingDelegate {
    
    // AR SceneKit View for camera rendering
    private var sceneView: ARSCNView!
    
    // Metal view for custom rendering (positioned on top of sceneView)
    private var arMetalView: FlameMetalView!
    
    // AR session
    private let arSession = ARSession()
    
    // Configuration
    private let configuration = ARImageTrackingConfiguration()
    
    // Tracked images information
    private var trackedImages: [ARReferenceImage] = []
    private var activeImageAnchors: [UUID: ARImageAnchor] = [:]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupARSession()
        setupARView()
        setupMetalView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Reset tracking and run session
        arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the session
        arSession.pause()
    }
    
    // MARK: - Setup
    
    private func setupARSession() {
        // Set delegate
        arSession.delegate = self
        
        // Load reference images
        guard let referenceImages = loadReferenceImages() else {
            fatalError("Failed to load reference images")
        }
        
        // Configure image tracking
        configuration.trackingImages = referenceImages
        configuration.maximumNumberOfTrackedImages = 2
        
        // Store reference to tracked images
        trackedImages = Array(referenceImages)
    }
    
    private func setupARView() {
        // Create ARSCNView for camera background rendering
        sceneView = ARSCNView(frame: view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(sceneView)
        
        // Use the shared session
        sceneView.session = arSession
        
        // Hide statistics
        sceneView.showsStatistics = false
        
        // Make scene view transparent except for camera
        sceneView.scene = SCNScene()
        sceneView.backgroundColor = .clear
        sceneView.isPlaying = true
        
        // Disable unnecessary features for better performance
        sceneView.antialiasingMode = .none
        sceneView.rendersCameraGrain = false
        sceneView.rendersMotionBlur = false
    }
    
    private func setupMetalView() {
        // Create Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        // Create AR Metal view with transparent background
        arMetalView = FlameMetalView(
            frame: view.bounds,
            device: device,
            session: arSession
        )
        arMetalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arMetalView.trackingDelegate = self
        
        // Make Metal view background transparent so we can see SceneKit view
        arMetalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        arMetalView.framebufferOnly = false
        arMetalView.backgroundColor = .clear
        arMetalView.isOpaque = false
        
        arMetalView.setView(viewSize: view.frame.size)
        view.addSubview(arMetalView)
        
        // Add specialized renderer for tracked images
        let imageTrackingRenderer = ImageTrackingRenderer(
            id: "imageTracker",
            config: RendererConfig(
                device: device,
                pixelFormat: arMetalView.colorPixelFormat,
                depthStencilFormat: arMetalView.depthStencilPixelFormat,
                sampleCount: arMetalView.sampleCount
            ), renderOrder: 0
        )
        
        imageTrackingRenderer.setup(device: device)
        arMetalView.addRenderer(imageTrackingRenderer, order: 50)
    }
    
    private func loadReferenceImages() -> Set<ARReferenceImage>? {
        // Load from asset catalog
        guard let referenceImages = ARReferenceImage.referenceImages(
            inGroupNamed: "AR Resources",
            bundle: Bundle.main
        ) else {
            print("Failed to load reference images from AR Resources")
            
            // Alternatively, create reference images programmatically
            return createReferenceImagesManually()
        }
        print("reference imgs \(referenceImages)")
        return referenceImages
    }
    
    private func createReferenceImagesManually() -> Set<ARReferenceImage>? {
        var images = Set<ARReferenceImage>()
        
        // Example: Create a reference image from a bundle resource
        if let image = UIImage(named: "test_img"),
           let cgImage = image.cgImage {
            
            // Create reference image with physical size in meters (adjust as needed)
            let referenceImage = ARReferenceImage(
                cgImage,
                orientation: .up,
                physicalWidth: 0.1 // 10 cm wide
            )
            referenceImage.name = "sample-image"
            
            images.insert(referenceImage)
        }
        
        return images.isEmpty ? nil : images
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Additional frame processing if needed
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor else { continue }
            
            print("Added image anchor: \(imageAnchor.name ?? "unnamed")")
            
            // Store active anchors
            activeImageAnchors[imageAnchor.identifier] = imageAnchor
            
            // Option 1: Add a SceneKit node for visualization (optional)
//             let node = createNodeForImageAnchor(imageAnchor)
//             sceneView.scene.rootNode.addChildNode(node)
            
            // Option 2: Update Metal renderer with the new image anchor
            if let renderer: ImageTrackingRenderer = arMetalView.getRenderer(id: "imageTracker") {
                renderer.trackImage(anchor: imageAnchor)
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor else { continue }
            
            // Update anchor information
            activeImageAnchors[imageAnchor.identifier] = imageAnchor
            
            // Update renderer with updated anchor
            if let imageTrackingRenderer: ImageTrackingRenderer = arMetalView.getRenderer(id: "imageTracker") {
                imageTrackingRenderer.updateImageTracking(anchor: imageAnchor)
            }
        }
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor else { continue }
            
            print("Removed image anchor: \(imageAnchor.name ?? "unnamed")")
            
            // Remove from active anchors
            activeImageAnchors.removeValue(forKey: imageAnchor.identifier)
            
            // Update renderer about removed anchor
            if let imageTrackingRenderer: ImageTrackingRenderer = arMetalView.getRenderer(id: "imageTracker"){
                imageTrackingRenderer.stopTrackingImage(anchorID: imageAnchor.identifier)
            }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Handle error
        print("AR session failed: \(error.localizedDescription)")
    }
    
    // MARK: - ARTrackingDelegate
    
    func trackingStateChanged(state: ARCamera.TrackingState, reason: ARCamera.TrackingState.Reason?) {
        DispatchQueue.main.async { [weak self] in
            self?.updateTrackingStateUI(state: state, reason: reason)
        }
    }
    
    private func updateTrackingStateUI(state: ARCamera.TrackingState, reason: ARCamera.TrackingState.Reason?) {
        // Update UI based on tracking state
        switch state {
        case .normal:
            // Show tracking UI
            break
        case .limited(let reason):
            // Show limited tracking UI with reason
            print("Limited tracking: \(reason)")
        case .notAvailable:
            // Show not available UI
            print("Tracking not available")
        }
    }
    
    // MARK: - Node Creation (Optional, for SceneKit visualization)
    
    private func createNodeForImageAnchor(_ imageAnchor: ARImageAnchor) -> SCNNode {
        // Create a plane to visualize the detected image
        let size = imageAnchor.referenceImage.physicalSize
        let plane = SCNPlane(width: size.width, height: size.height)
        
        // Make it semi-transparent
        plane.firstMaterial?.diffuse.contents = UIColor.yellow.withAlphaComponent(0.6)
        
        // Create node
        let node = SCNNode(geometry: plane)
        
        // Rotate it (SCNPlane is vertical by default)
        node.eulerAngles.x = -Float.pi / 2
        
        // Create parent node to align with the image anchor
        let anchorNode = SCNNode()
        anchorNode.addChildNode(node)
        
        // Set the name for identification
        anchorNode.name = imageAnchor.name ?? "unnamed-image"
        
        return anchorNode
    }
}
