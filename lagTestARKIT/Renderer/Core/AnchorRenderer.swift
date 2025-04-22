//
//  AnchorRenderer.swift
//  lagTestARKIT
//
//  Created by Vishwas Prakash on 22/04/25.
//

import Foundation
import Metal
import MetalKit
import ARKit

/// Renders 3D objects at AR anchor positions
class AnchorRenderer: BaseRenderer {
    // Mesh for anchors
    private var cubeMesh: MTKMesh?
    
    // Anchor-specific
    private var anchorPipelineState: MTLRenderPipelineState?
    private var anchorDepthState: MTLDepthStencilState?
    private var anchorCount: Int = 0
    
    // Vertex descriptor for anchor geometry
    private var geometryVertexDescriptor: MTLVertexDescriptor?
    
    // Buffer indices
    enum BufferIndex: Int {
        case meshPositions = 0
        case meshGenerics = 1
        case uniforms = 2
        case instanceUniforms = 3
    }
    
    // Attribute indices
    enum VertexAttribute: Int {
        case position = 0
        case texcoord = 1
        case normal = 2
    }
    
    // Render order - should be after background
    override var renderOrder: Int {
        get {
            return super.renderOrder
        }
        set {
            super.renderOrder = newValue
        }
    }
    
    // Custom meshes that can be rendered at anchor positions
    private var meshes: [String: MTKMesh] = [:]
    
    // Update anchor instance count
    func updateAnchorCount(_ count: Int) {
        anchorCount = count
    }
    
    override func setup(device: MTLDevice, library: MTLLibrary) {
        super.setup(device: device, library: library)
        
        // Create vertex descriptor
        setupVertexDescriptor()
        
        // Create pipeline state
        setupRenderPipeline(device: device, library: library)
        
        // Load default cube mesh
        loadDefaultMesh(device: device)
    }
    
    private func setupVertexDescriptor() {
        geometryVertexDescriptor = MTLVertexDescriptor()
        
        // Position attribute
        geometryVertexDescriptor?.attributes[VertexAttribute.position.rawValue].format = .float3
        geometryVertexDescriptor?.attributes[VertexAttribute.position.rawValue].offset = 0
        geometryVertexDescriptor?.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue
        
        // Texture coordinate attribute
        geometryVertexDescriptor?.attributes[VertexAttribute.texcoord.rawValue].format = .float2
        geometryVertexDescriptor?.attributes[VertexAttribute.texcoord.rawValue].offset = 0
        geometryVertexDescriptor?.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue
        
        // Normal attribute
        geometryVertexDescriptor?.attributes[VertexAttribute.normal.rawValue].format = .half3
        geometryVertexDescriptor?.attributes[VertexAttribute.normal.rawValue].offset = 8
        geometryVertexDescriptor?.attributes[VertexAttribute.normal.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue
        
        // Buffer layouts
        geometryVertexDescriptor?.layouts[BufferIndex.meshPositions.rawValue].stride = 12 // float3
        geometryVertexDescriptor?.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
        geometryVertexDescriptor?.layouts[BufferIndex.meshPositions.rawValue].stepFunction = .perVertex
        
        geometryVertexDescriptor?.layouts[BufferIndex.meshGenerics.rawValue].stride = 16 // float2 + half3 + padding
        geometryVertexDescriptor?.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
        geometryVertexDescriptor?.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = .perVertex
    }
    
    private func setupRenderPipeline(device: MTLDevice, library: MTLLibrary) {
        guard let vertexFunction = library.makeFunction(name: "anchorGeometryVertexTransform"),
              let fragmentFunction = library.makeFunction(name: "anchorGeometryFragmentLighting") else {
            print("Failed to find anchor geometry shader functions")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "AnchorGeometryPipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.vertexDescriptor = geometryVertexDescriptor
        pipelineDescriptor.colorAttachments[0].pixelFormat = config.pixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = config.depthStencilFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = config.depthStencilFormat
        
        do {
            anchorPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("Failed to create anchor geometry pipeline state: \(error)")
        }
        
        // Create depth stencil state
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.depthCompareFunction = .less
        depthStateDescriptor.isDepthWriteEnabled = true
        anchorDepthState = device.makeDepthStencilState(descriptor: depthStateDescriptor)
    }
    
    private func loadDefaultMesh(device: MTLDevice) {
        // Create a MetalKit mesh buffer allocator so that ModelIO will load mesh data directly into
        // Metal buffers accessible by the GPU
        let metalAllocator = MTKMeshBufferAllocator(device: device)
        
        // Create a Model IO vertex descriptor so that we format/layout our model IO mesh vertices to
        // fit our Metal render pipeline's vertex descriptor layout
        guard let vertexDescriptor = geometryVertexDescriptor else { return }
        
        let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)
        
        // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
        guard let attributes = mdlVertexDescriptor.attributes as? [MDLVertexAttribute] else { return }
        attributes[VertexAttribute.position.rawValue].name = MDLVertexAttributePosition
        attributes[VertexAttribute.texcoord.rawValue].name = MDLVertexAttributeTextureCoordinate
        attributes[VertexAttribute.normal.rawValue].name = MDLVertexAttributeNormal
        
        // Use ModelIO to create a box mesh as our object
        let mesh = MDLMesh(boxWithExtent: SIMD3<Float>(0.075, 0.075, 0.075),
                          segments: SIMD3<UInt32>(1, 1, 1),
                          inwardNormals: false,
                          geometryType: .triangles,
                          allocator: metalAllocator)
        
        // Perform the format/relayout of mesh vertices by setting the vertex descriptor in our
        // Model IO mesh
        mesh.vertexDescriptor = mdlVertexDescriptor
        
        // Create a MetalKit mesh (and submeshes) backed by Metal buffers
        do {
            cubeMesh = try MTKMesh(mesh: mesh, device: device)
        } catch {
            print("Error creating MetalKit mesh: \(error)")
        }
    }
    
    // Add a custom mesh to use for anchors
    func addMesh(id: String, mesh: MTKMesh) {
        meshes[id] = mesh
    }
    
    override func draw(renderEncoder: MTLRenderCommandEncoder,
                      uniformBuffer: MTLBuffer,
                       uniformBufferOffset: Int) {
        // Skip if no anchors or mesh
        guard anchorCount > 0,
              let cubeMesh = cubeMesh,
              let anchorPipelineState = anchorPipelineState,
              let anchorDepthState = anchorDepthState else {
            return
        }
        
        renderEncoder.pushDebugGroup("DrawAnchors")
        
        renderEncoder.setCullMode(.back)
        renderEncoder.setRenderPipelineState(anchorPipelineState)
        renderEncoder.setDepthStencilState(anchorDepthState)
        
        // Get uniform buffer offset from the base instance uniform offset
        // This is set by the ARRenderingEngine in updateBufferStates()
        let instanceUniformBufferOffset = uniformBufferOffset + MemoryLayout<SharedUniforms>.size
        
        // Set shared uniform buffer for transforms
        renderEncoder.setVertexBuffer(uniformBuffer, offset: instanceUniformBufferOffset, index: BufferIndex.instanceUniforms.rawValue)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setFragmentBuffer(uniformBuffer, offset: uniformBufferOffset, index: BufferIndex.uniforms.rawValue)
        
        // Set mesh's vertex buffer
        for bufferIndex in 0..<cubeMesh.vertexBuffers.count {
            let vertexBuffer = cubeMesh.vertexBuffers[bufferIndex]
            renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index: bufferIndex)
        }
        
        // Draw each submesh of our mesh
        for submesh in cubeMesh.submeshes {
            renderEncoder.drawIndexedPrimitives(
                type: submesh.primitiveType,
                indexCount: submesh.indexCount,
                indexType: submesh.indexType,
                indexBuffer: submesh.indexBuffer.buffer,
                indexBufferOffset: submesh.indexBuffer.offset,
                instanceCount: anchorCount
            )
        }
        
        renderEncoder.popDebugGroup()
    }
}
