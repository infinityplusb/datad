/**
 * Canonical plottable record shared by ida-server and ida-client (local ingest).
 * Renderer-agnostic: no Vulkan or ECS types.
 */
module plot;

import quat_math;

/// Rotation as quaternion **w, x, y, z** (Hamilton convention; identity **1,0,0,0**).
struct PlotRotation
{
    float w = 1.0f;
    float x;
    float y;
    float z;

    static PlotRotation identity() { return PlotRotation(1.0f, 0.0f, 0.0f, 0.0f); }

    static PlotRotation fromEulerRad(float rx, float ry, float rz)
    {
        PlotRotation r;
        eulerRadToQuat(rx, ry, rz, r.w, r.x, r.y, r.z);
        return r;
    }
}

/** RGBA in linear-ish float space (matches existing addColor usage). */
struct PlotColor
{
    float r = 1.0f;
    float g = 1.0f;
    float b = 1.0f;
    float a = 1.0f;
}

/**
 * One drawable instance: position, scale, optional mesh asset path, colour, quaternion rotation, velocity.
 * `meshPath`: empty means the app uses a default primitive (e.g. cube); non-empty paths are resolved with `ida.data.format_.loadMeshByPath` in the app.
 * `attributes`: optional KEY=VAL strings passed through to network/entity metadata.
 */
struct PlottableEntity
{
    float x;
    float y;
    float z;
    float scaleX = 1.0f;
    float scaleY = 1.0f;
    float scaleZ = 1.0f;
    string meshPath;
    PlotColor color;
    PlotRotation rotation;
    float vx;
    float vy;
    float vz;
    string name;
    string[] attributes;
}

/** Mirrors server Application.variableDisplayState for axis remapping in the client. */
struct PlotVariableDisplayState
{
    bool valid;
    int nColumns;
    string[] columnNames;
    int[3] axisIndices = [0, 1, 2];
    float scale = 4.0f;
}

/** Result of a generic file ingest: entities plus UI mapping metadata. */
struct PlotIngestResult
{
    PlottableEntity[] entities;
    PlotVariableDisplayState variableDisplay;
}
