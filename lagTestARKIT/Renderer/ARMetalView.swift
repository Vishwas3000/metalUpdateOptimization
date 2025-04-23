//
//  ARMetalView.swift
//  lagTestARKIT
//
//  Created by Vishwas Prakash on 21/04/25.
//

import Foundation
import Metal
import MetalKit
import ARKit

/// Protocol defining the interface for receiving AR rendered content
protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

/// Main AR view that integrates Metal rendering with ARKit
class ARMetalView: MTKView, RenderDestinationProvider {
    // AR session
    var session: ARSession!
    
    // Rendering engine
    private var renderingEngine: ARRenderingEngine!
    
    // Tracking state
    private var trackingState: ARCamera.TrackingState = .notAvailable
    
    // Delegate for receiving tracking state changes
    weak var trackingDelegate: ARTrackingDelegate?
    
    // MARK: - Initialization
    
    init(frame: CGRect, device: MTLDevice, session: ARSession) {
        super.init(frame: frame, device: device)
        
        self.session = session
        
        // Configure view properties
        self.colorPixelFormat = .bgra8Unorm
        self.depthStencilPixelFormat = .depth32Float_stencil8
        self.sampleCount = 1
        self.isOpaque = true
        self.backgroundColor = .blue
        
        // Setup rendering engine
        renderingEngine = ARRenderingEngine(session: session, device: device, renderDestination: self, viewportSize: self.bounds.size)
        
        // Configure delegate for draw calls
        self.delegate = self
        
        // Enable continuous rendering by default
        self.enableSetNeedsDisplay = false
        self.isPaused = false
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Public Interface
    
    /// Get a specific renderer by ID for customization
    func getRenderer<T: Renderer>(id: String) -> T? {
        return renderingEngine.getRenderer<T>(id: id)
    }
    
    /// Add a custom renderer
    func addRenderer(_ renderer: Renderer, order: Int) {
        renderingEngine.addRenderer(renderer, order: order)
    }
    
    /// Remove a renderer by ID
    func removeRenderer(id: String) {
        renderingEngine.removeRenderer(id: id)
    }
    
    /// Update the tracking state
    func updateTrackingState(_ state: ARCamera.TrackingState, reason: ARCamera.TrackingState.Reason? = nil) {
        if trackingState != state {
            trackingState = state
            trackingDelegate?.trackingStateChanged(state: state, reason: reason)
        }
    }
    
    public func setView(viewSize: CGSize){
        renderingEngine.drawRectResized(size: viewSize)
    }
}

// MARK: - MTKViewDelegate

extension ARMetalView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderingEngine.drawRectResized(size: size)
    }
    
    func draw(in view: MTKView) {
        // Update tracking state if available
        if let camera = session.currentFrame?.camera {
            updateTrackingState(camera.trackingState, reason: nil)
        }
        
        // Perform rendering
        renderingEngine.update()
    }
}

// MARK: - Tracking Delegate Protocol

protocol ARTrackingDelegate: AnyObject {
    func trackingStateChanged(state: ARCamera.TrackingState, reason: ARCamera.TrackingState.Reason?)
}
