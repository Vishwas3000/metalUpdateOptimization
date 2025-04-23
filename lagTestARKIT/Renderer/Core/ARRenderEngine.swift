//
//  ARRenderEngine.swift
//  lagTestARKIT
//
//  Created by Vishwas Prakash on 21/04/25.
//

import Foundation
import Metal
import MetalKit
import ARKit

/// Main rendering engine that coordinates multiple specialized renderers
class ARRenderingEngine {
    // Core properties
    private let device: MTLDevice
    private var renderDestination: RenderDestinationProvider
    private let session: ARSession
    
    // Semaphore to prevent too many frames in flight
    private let inFlightSemaphore = DispatchSemaphore(value: 3)
    
    // The render coordinator that manages all renderers
    private let renderCoordinator: RenderCoordinator
    
    // Viewport tracking
    private var viewportSize: CGSize
    private var viewportSizeDidChange = false
    
    // Texture management
    private var textureCache: CVMetalTextureCache?
    
    // MARK: - Initialization
    
    init(session: ARSession, device: MTLDevice, renderDestination: RenderDestinationProvider, viewportSize: CGSize) {
        self.session = session
        self.device = device
        self.viewportSize = viewportSize
        self.renderDestination = renderDestination
        
        // Configure render destination formats
        self.renderDestination.colorPixelFormat = .bgra8Unorm
        self.renderDestination.depthStencilPixelFormat = .depth32Float_stencil8
        self.renderDestination.sampleCount = 1
        
        // Create the render coordinator
        self.renderCoordinator = RenderCoordinator(device: device, viewportSize: viewportSize)
        
        // Create texture cache
        createTextureCache()
        
        // Load default renderers
        setupDefaultRenderers()
    }
    
    private func createTextureCache() {
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        textureCache = cache
    }
    
    private func setupDefaultRenderers() {
        // Create configuration
        let config = RendererConfig(
            device: device,
            pixelFormat: renderDestination.colorPixelFormat,
            depthStencilFormat: renderDestination.depthStencilPixelFormat,
            sampleCount: renderDestination.sampleCount
        )
        
        // Create default library
        guard let library = device.makeDefaultLibrary() else {
            print("Failed to load default Metal library")
            return
        }
        
        // Here you can add your default renderers, for example:
        
        // Example: Add a background renderer for camera feed
        // let backgroundRenderer = BackgroundRenderer(id: "background", config: config, renderOrder: 0)
        // backgroundRenderer.setup(device: device, library: library)
        // renderCoordinator.addRenderer(backgroundRenderer)
        
        // Example: Add a renderer for AR anchors
        // let anchorRenderer = AnchorRenderer(id: "anchors", config: config, renderOrder: 100)
        // anchorRenderer.setup(device: device, library: library)
        // renderCoordinator.addRenderer(anchorRenderer)
        
        // Example: Add an image tracking renderer
        // let imageTrackingRenderer = ImageTrackingRenderer(id: "imageTracker", config: config, renderOrder: 200)
        // imageTrackingRenderer.setup(device: device, library: library)
        // renderCoordinator.addRenderer(imageTrackingRenderer)
    }
    
    // MARK: - Renderer Management
    
    func addRenderer(_ renderer: Renderer, order: Int) {
        // Set the render order
        renderer.renderOrder = order
        
        // Setup the renderer if not already setup
        if let library = device.makeDefaultLibrary() {
            renderer.setup(device: device, library: library)
        }
        
        // Add to the coordinator
        renderCoordinator.addRenderer(renderer)
    }
    
    func removeRenderer(id: String) {
        renderCoordinator.removeRenderer(id: id)
    }
    
    func getRenderer<T: Renderer>(id: String) -> T? {
        return renderCoordinator.renderers.first(where: { $0.id == id }) as? T
    }
    
    // MARK: - Rendering Loop
    
    func update() {
        // Wait for the inflight semaphore
        let _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        // Get current frame from AR session
        guard let frame = session.currentFrame else {
            inFlightSemaphore.signal()
            return
        }
        
        // Update the coordinator with the current frame
        renderCoordinator.update(frame: frame)
        
        // Handle viewport changes
        if viewportSizeDidChange {
            viewportSizeDidChange = false
            renderCoordinator.resize(size: viewportSize)
        }
        
        // Draw the frame
        draw()
    }
    
    func draw() {
        // Use the coordinator to handle the drawing
        renderCoordinator.draw(renderDestination: renderDestination)
        
        // Signal the semaphore
        inFlightSemaphore.signal()
    }
    
    // MARK: - Texture Utilities
    
    func createTextureFromPixelBuffer(_ pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache!,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            planeIndex,
            &texture
        )
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
    // MARK: - Viewport Management
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
        print("viewport size: \(viewportSize)")
        viewportSizeDidChange = true
    }
}
