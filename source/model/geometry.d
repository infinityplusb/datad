module geometry;

/** Vertex attributes for mesh data from files (OBJ, FBX, etc.). No renderer bindings. */
struct GeometryVertex
{
    float[3] pos = [0.0f, 0.0f, 0.0f];
    float[3] color = [1.0f, 1.0f, 1.0f];
    float[3] normal = [0.5f, 0.5f, 0.0f];
    float[3] texCoord = [0.5f, 0.5f, 0.0f];
}
