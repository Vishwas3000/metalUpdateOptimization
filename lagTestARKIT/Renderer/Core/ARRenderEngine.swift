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
    private let commandQueue: MTLCommandQueue
    private var renderDestination: RenderDestinationProvider
    private let session: ARSession
    
    // Semaphore to prevent too many frames in flight
    private let kMaxBuffersInFlight = 3
    private let inFlightSemaphore = DispatchSemaphore(value: 3)
    
    // Renderer collection
    private var renderers: [String: Renderer] = [:]
    private var renderOrder: [String] = []
    
    // Buffer management
    private var uniformBufferIndex = 0
    private var sharedUniformBuffer: MTLBuffer
    private var anchorUniformBuffer: MTLBuffer
    
    // Alignment for uniform buffers
    private let kAlignedSharedUniformsSize: Int
    private let kAlignedInstanceUniformsSize: Int
    
    // Current offsets in the uniform buffers
    private var sharedUniformBufferOffset = 0
    private var anchorUniformBufferOffset = 0
    
    // Viewport tracking
    private var viewportSize: CGSize = .zero
    private var viewportSizeDidChange = false
    
    // Texture management
    private var textureCache: CVMetalTextureCache?
    
    // Maximum number of anchors to track
    private let kMaxAnchorInstanceCount = 64
    
    // MARK: - Initialization
    
    init(session: ARSession, device: MTLDevice, renderDestination: RenderDestinationProvider) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        
        // Create command queue
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        commandQueue = queue
        
        // Configure render destination formats
        self.renderDestination.colorPixelFormat = .bgra8Unorm
        self.renderDestination.depthStencilPixelFormat = .depth32Float_stencil8
        self.renderDestination.sampleCount = 1
        
        // Calculate buffer alignments
        kAlignedSharedUniformsSize = (MemoryLayout<SharedUniforms>.size & ~0xFF) + 0x100
        kAlignedInstanceUniformsSize = ((MemoryLayout<InstanceUniforms>.size * kMaxAnchorInstanceCount) & ~0xFF) + 0x100
        
        // Create uniform buffers
        let sharedUniformBufferSize = kAlignedSharedUniformsSize * kMaxBuffersInFlight
        let anchorUniformBufferSize = kAlignedInstanceUniformsSize * kMaxBuffersInFlight
        
        sharedUniformBuffer = device.makeBuffer(length: sharedUniformBufferSize, options: .storageModeShared)!
        sharedUniformBuffer.label = "SharedUniformBuffer"
        
        anchorUniformBuffer = device.makeBuffer(length: anchorUniformBufferSize, options: .storageModeShared)!
        anchorUniformBuffer.label = "AnchorUniformBuffer"
        
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
        
        // Create and add background renderer (for camera feed)
        //        let backgroundRenderer = BackgroundRenderer(id: "background", config: config)
        //        backgroundRenderer.setup(device: device, library: library)
        //        addRenderer(backgroundRenderer, order: 0)
        //
        // Create anchor renderer (for AR content)
        //        let anchorRenderer = AnchorRenderer(id: "anchors", config: config)
        //        anchorRenderer.setup(device: device, library: library)
        //        addRenderer(anchorRenderer, order: 100)
    }
    
    // MARK: - Renderer Management
    
    func addRenderer(_ renderer: Renderer, order: Int) {
        renderers[renderer.id] = renderer
        
        // Insert renderer ID in the correct position based on order
        if let existingIndex = renderOrder.firstIndex(of: renderer.id) {
            renderOrder.remove(at: existingIndex)
        }
        
        // Find insertion point based on order
        var insertionIndex = renderOrder.count
        for (index, rendererID) in renderOrder.enumerated() {
            if let existingRenderer = renderers[rendererID], existingRenderer.renderOrder > order {
                insertionIndex = index
                break
            }
        }
        
        renderOrder.insert(renderer.id, at: insertionIndex)
    }
    
    func removeRenderer(id: String) {
        renderers.removeValue(forKey: id)
        if let index = renderOrder.firstIndex(of: id) {
            renderOrder.remove(at: index)
        }
    }
    
    func getRenderer<T: Renderer>(id: String) -> T? {
        return renderers[id] as? T
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
        
        // Update buffer states
        updateBufferStates()
        
        // Update shared uniforms
        updateSharedUniforms(frame: frame)
        
        // Update anchors
        updateAnchors(frame: frame)
        
        // Update all renderers
        for rendererID in renderOrder {
            if let renderer = renderers[rendererID], renderer.isEnabled {
                renderer.update(frame: frame)
            }
        }
        
        // Handle viewport changes
        if viewportSizeDidChange {
            viewportSizeDidChange = false
            for rendererID in renderOrder {
                if let renderer = renderers[rendererID] {
                    renderer.resize(size: viewportSize)
                }
            }
        }
        
        // Draw
        draw()
    }
    
    func draw() {
        // Create a command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlightSemaphore.signal()
            return
        }
        
        commandBuffer.label = "MainRenderPass"
        
        // Add completion handler to signal the semaphore when done
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
        }
        
        // Check if we have a valid render pass descriptor and drawable
        guard let renderPassDescriptor = renderDestination.currentRenderPassDescriptor,
              let currentDrawable = renderDestination.currentDrawable else {
            inFlightSemaphore.signal()
            return
        }
        
        // Create render encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            inFlightSemaphore.signal()
            return
        }
        
        renderEncoder.label = "MainRenderEncoder"
        
        // Draw each renderer in order
        for rendererID in renderOrder {
            if let renderer = renderers[rendererID], renderer.isEnabled {
                renderEncoder.pushDebugGroup(renderer.id)
                renderer.draw(
                    renderEncoder: renderEncoder,
                    uniformBuffer: sharedUniformBuffer,
                    uniformBufferOffset: sharedUniformBufferOffset
                )
                renderEncoder.popDebugGroup()
            }
        }
        
        // End encoding
        renderEncoder.endEncoding()
        
        // Present the drawable
        commandBuffer.present(currentDrawable)
        
        // Commit the command buffer
        commandBuffer.commit()
    }
    
    // MARK: - Buffer Management
    
    private func updateBufferStates() {
        uniformBufferIndex = (uniformBufferIndex + 1) % kMaxBuffersInFlight
        
        sharedUniformBufferOffset = kAlignedSharedUniformsSize * uniformBufferIndex
        anchorUniformBufferOffset = kAlignedInstanceUniformsSize * uniformBufferIndex
    }
    
    private func updateSharedUniforms(frame: ARFrame) {
        let uniforms = sharedUniformBuffer.contents()
            .advanced(by: sharedUniformBufferOffset)
            .assumingMemoryBound(to: SharedUniforms.self)
        
        let viewmatrix = frame.camera.viewMatrix(for: .portrait)
        let projectionMatrix = frame.camera.projectionMatrix(
            for: .portrait,
            viewportSize: viewportSize,
            zNear: 0.001,
            zFar: 1000
        )
        uniforms.pointee.viewMatrix = viewmatrix

        uniforms.pointee.projectionMatrix = projectionMatrix
        
        // Update lighting based on ARFrame light estimate
        var ambientIntensity: Float = 1.0
        
        if let lightEstimate = frame.lightEstimate {
            ambientIntensity = Float(lightEstimate.ambientIntensity) / 1000.0
        }
        
        let ambientLightColor: vector_float3 = vector3(0.5, 0.5, 0.5)
        uniforms.pointee.ambientLightColor = ambientLightColor * ambientIntensity
        
        let directionalLightDirection = simd_normalize(vector3(0.0, 0.0, -1.0))
//        uniforms.pointee.directionalLightDirection = directionalLightDirection
        
        let directionalLightColor: vector_float3 = vector3(0.6, 0.6, 0.6)
        uniforms.pointee.directionalLightColor = directionalLightColor * ambientIntensity
        
        uniforms.pointee.materialShininess = 30
    }
    
    private func updateAnchors(frame: ARFrame) {
        let uniformBufferAddress = anchorUniformBuffer.contents()
            .advanced(by: anchorUniformBufferOffset)
            .assumingMemoryBound(to: InstanceUniforms.self)
        
        let anchorCount = min(frame.anchors.count, kMaxAnchorInstanceCount)
        
        var anchorOffset = 0
        if anchorCount == kMaxAnchorInstanceCount {
            anchorOffset = max(frame.anchors.count - kMaxAnchorInstanceCount, 0)
        }
        for index in 0..<anchorCount {
            let anchor = frame.anchors[index + anchorOffset]
            
            // Flip Z axis to convert from right-handed to left-handed coords
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            let modelMatrix = simd_mul(anchor.transform, coordinateSpaceTransform)
            
            uniformBufferAddress[index].modelMatrix = modelMatrix
        }
        
        // Update any anchor-specific renderers with the count
        if let anchorRenderer = renderers["anchors"] as? AnchorRenderer {
            anchorRenderer.updateAnchorCount(anchorCount)
        }
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
        print("view port size: \(viewportSize)")
        viewportSizeDidChange = true
    }
}
