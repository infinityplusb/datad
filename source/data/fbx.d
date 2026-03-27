module fbx;

import std.algorithm;
import std.conv;
import std.file : read;
import std.stdio;
import std.string;
import std.typecons : Tuple, tuple;

import geometry : GeometryVertex;

enum FBX_BINARY_MAGIC_LEN = 21;

Tuple!(GeometryVertex[], int[]) loadFbx(in string filename)
{
    debug (FbxLoader) writeln("Loading FBX from: ", filename);
    ubyte[] raw = cast(ubyte[]) read(filename);
    bool isBinary = raw.length >= FBX_BINARY_MAGIC_LEN
        && raw[0 .. FBX_BINARY_MAGIC_LEN].equal("Kaydara FBX Binary  \x00".representation);
    if (isBinary)
        return loadFbxBinary(raw);
    string content = cast(string) raw;
    return loadFbxFromString(content);
}

private Tuple!(GeometryVertex[], int[]) loadFbxBinary(const ubyte[] data)
{
    if (data.length < 27)
        throw new Exception("FBX binary: file too short");
    double[] verticesData;
    int[] polygonVertexIndices;
    parseFbxBinaryNodes(data, 27, data.length, &verticesData, &polygonVertexIndices);
    if (verticesData.length == 0 || polygonVertexIndices.length == 0)
        throw new Exception("FBX binary: no geometry found (Vertices and PolygonVertexIndex required)");
    return buildMeshFromGeometry(verticesData, polygonVertexIndices);
}

private bool parseFbxBinaryNodes(const ubyte[] data, size_t offset, size_t endOffset,
        double[]* pVertices, int[]* pIndices)
{
    if (offset + 13 > endOffset)
        return false;
    uint endOff = *cast(const uint*)(data.ptr + offset);
    uint numProps = *cast(const uint*)(data.ptr + offset + 4);
    ubyte nameLen = data[offset + 12];
    size_t at = offset + 13;
    if (at + nameLen > endOffset)
        return false;
    string nodeName = cast(string) data[at .. at + nameLen].dup;
    at += nameLen;
    double[] verts;
    int[] indices;
    for (uint i = 0; i < numProps && at < endOffset; i++)
    {
        if (at >= endOffset)
            break;
        char tc = cast(char) data[at++];
        if (tc == 'L' || tc == 'l')
        {
            at += 8;
            continue;
        }
        if (tc == 'D' || tc == 'F')
        {
            at += (tc == 'D' ? 8 : 4);
            continue;
        }
        if (tc == 'I' || tc == 'Y')
        {
            at += (tc == 'I' ? 4 : 2);
            continue;
        }
        if (tc == 'C')
        {
            at += 1;
            continue;
        }
        if (tc == 'R' || tc == 'S')
        {
            if (at + 4 > endOffset)
                break;
            uint len = *cast(const uint*)(data.ptr + at);
            at += 4 + len;
            continue;
        }
        if (tc == 'd' || tc == 'f')
        {
            if (at + 12 > endOffset)
                break;
            uint arrayLen = *cast(const uint*)(data.ptr + at);
            uint encoding = *cast(const uint*)(data.ptr + at + 4);
            uint compLen = *cast(const uint*)(data.ptr + at + 8);
            at += 12;
            if (encoding == 0 && arrayLen > 0 && (arrayLen % 3) == 0)
            {
                uint elemSize = (tc == 'd') ? 8u : 4u;
                if (at + arrayLen * elemSize <= endOffset && verts.length == 0)
                {
                    for (uint j = 0; j < arrayLen; j += 3)
                    {
                        if (tc == 'd')
                        {
                            double x = *cast(const double*)(data.ptr + at + j * 8);
                            double y = *cast(const double*)(data.ptr + at + (j + 1) * 8);
                            double z = *cast(const double*)(data.ptr + at + (j + 2) * 8);
                            verts ~= [x, y, z];
                        }
                        else
                        {
                            float x = *cast(const float*)(data.ptr + at + j * 4);
                            float y = *cast(const float*)(data.ptr + at + (j + 1) * 4);
                            float z = *cast(const float*)(data.ptr + at + (j + 2) * 4);
                            verts ~= [cast(double) x, cast(double) y, cast(double) z];
                        }
                    }
                }
                at += arrayLen * elemSize;
            }
            else if (encoding == 1)
                at += compLen;
            continue;
        }
        if (tc == 'i')
        {
            if (at + 12 > endOffset)
                break;
            uint arrayLen = *cast(const uint*)(data.ptr + at);
            uint encoding = *cast(const uint*)(data.ptr + at + 4);
            uint compLen = *cast(const uint*)(data.ptr + at + 8);
            at += 12;
            if (encoding == 0 && arrayLen > 0)
            {
                if (at + arrayLen * 4 <= endOffset && indices.length == 0)
                {
                    for (uint j = 0; j < arrayLen; j++)
                        indices ~= *cast(const int*)(data.ptr + at + j * 4);
                }
                at += arrayLen * 4;
            }
            else if (encoding == 1)
                at += compLen;
            continue;
        }
        if (tc == 'b')
        {
            at += 12;
            uint n = *cast(const uint*)(data.ptr + at - 12);
            at += n;
            continue;
        }
    }
    if (nodeName == "Geometry" && verts.length > 0 && indices.length > 0)
    {
        *pVertices = verts;
        *pIndices = indices;
        return true;
    }
    while (at + 13 <= endOff && at < endOffset)
    {
        uint nextEnd = *cast(const uint*)(data.ptr + at);
        if (nextEnd == 0 && *cast(const uint*)(data.ptr + at + 4) == 0)
            break;
        if (parseFbxBinaryNodes(data, at, nextEnd, pVertices, pIndices))
            return true;
        at = nextEnd;
    }
    return false;
}

private Tuple!(GeometryVertex[], int[]) buildMeshFromGeometry(double[] verticesData, int[] polygonVertexIndices)
{
    float[][] controlPoints;
    for (size_t i = 0; i + 2 < verticesData.length; i += 3)
        controlPoints ~= [[cast(float) verticesData[i], cast(float) verticesData[i + 1],
                cast(float) verticesData[i + 2]]];
    int[] triIndices;
    size_t k = 0;
    while (k < polygonVertexIndices.length)
    {
        int[] poly;
        while (k < polygonVertexIndices.length)
        {
            int idx = polygonVertexIndices[k++];
            if (idx < 0)
            {
                poly ~= (-idx) - 1;
                break;
            }
            poly ~= idx;
        }
        if (poly.length == 3)
            triIndices ~= [poly[0], poly[1], poly[2]];
        else if (poly.length >= 4)
            for (uint q = 1; q + 1 < poly.length; q++)
                triIndices ~= [poly[0], poly[q], poly[q + 1]];
    }
    GeometryVertex[] vertices;
    int[] indices;
    float[3] defaultNormal = [0.0f, 1.0f, 0.0f];
    float[3] defaultUv = [0.0f, 0.0f, 0.0f];
    for (size_t t = 0; t < triIndices.length; t += 3)
    {
        for (uint c = 0; c < 3; c++)
        {
            int cpIdx = triIndices[t + c];
            GeometryVertex v;
            v.pos[0] = controlPoints[cpIdx][0];
            v.pos[1] = -controlPoints[cpIdx][1];
            v.pos[2] = controlPoints[cpIdx][2];
            v.normal = defaultNormal;
            v.texCoord = defaultUv;
            v.color = [1.0f, 1.0f, 1.0f];
            vertices ~= v;
            indices ~= cast(int)(vertices.length - 1);
        }
    }
    debug (FbxLoader) writeln("FBX loaded: ", vertices.length, " vertices, ", indices.length, " indices");
    return tuple(vertices, indices);
}

Tuple!(GeometryVertex[], int[]) loadFbxFromString(in string content)
{
    float[][] controlPoints;
    int[] polygonVertexIndices;
    float[][] normals;
    float[][] uvs;

    int braceDepth = 0;
    size_t lineIdx = 0;
    string line;

    string[] lines = content.splitLines();
    for (; lineIdx < lines.length; lineIdx++)
    {
        line = lines[lineIdx].strip();
        if (line.length == 0 || line.startsWith(";"))
            continue;

        if (line.startsWith("Geometry:") && line.endsWith("{"))
        {
            braceDepth = 1;
            lineIdx++;
            while (lineIdx < lines.length && braceDepth > 0)
            {
                string inner = lines[lineIdx].strip();
                if (inner.startsWith(";"))
                {
                    lineIdx++;
                    continue;
                }
                foreach (char c; inner)
                {
                    if (c == '{')
                        braceDepth++;
                    else if (c == '}')
                        braceDepth--;
                }
                if (braceDepth <= 0)
                    break;

                if (inner.startsWith("Vertices:"))
                {
                    controlPoints = parseFbxFloat3Array(inner, "Vertices:");
                    lineIdx++;
                    continue;
                }
                if (inner.startsWith("PolygonVertexIndex:"))
                {
                    polygonVertexIndices = parseFbxIntArray(inner, "PolygonVertexIndex:");
                    lineIdx++;
                    continue;
                }
                if (inner.startsWith("LayerElementNormal:"))
                {
                    int subDepth = 0;
                    size_t j = lineIdx;
                    for (; j < lines.length; j++)
                    {
                        string l = lines[j];
                        foreach (char c; l)
                        {
                            if (c == '{')
                                subDepth++;
                            else if (c == '}')
                                subDepth--;
                        }
                        if (l.strip().startsWith("Normals:") && subDepth > 0)
                        {
                            normals = parseFbxFloat3FromLine(lines[j], "Normals:");
                            break;
                        }
                        if (subDepth < 0)
                            break;
                    }
                    lineIdx++;
                    continue;
                }
                if (inner.startsWith("LayerElementUV:"))
                {
                    int subDepth = 0;
                    size_t j = lineIdx;
                    for (; j < lines.length; j++)
                    {
                        string l = lines[j];
                        foreach (char c; l)
                        {
                            if (c == '{')
                                subDepth++;
                            else if (c == '}')
                                subDepth--;
                        }
                        if (l.strip().startsWith("UV:") && subDepth > 0)
                        {
                            uvs = parseFbxFloat2FromLine(lines[j], "UV:");
                            break;
                        }
                        if (subDepth < 0)
                            break;
                    }
                    lineIdx++;
                    continue;
                }
                lineIdx++;
            }
            if (controlPoints.length > 0 && polygonVertexIndices.length > 0)
                break;
        }
    }

    if (controlPoints.length == 0 || polygonVertexIndices.length == 0)
        throw new Exception("FBX: no geometry found (Vertices and PolygonVertexIndex required)");

    int[] triIndices;
    size_t k = 0;
    while (k < polygonVertexIndices.length)
    {
        int[] poly;
        while (k < polygonVertexIndices.length)
        {
            int idx = polygonVertexIndices[k++];
            if (idx < 0)
            {
                poly ~= (-idx) - 1;
                break;
            }
            poly ~= idx;
        }
        if (poly.length == 3)
            triIndices ~= [poly[0], poly[1], poly[2]];
        else if (poly.length >= 4)
            for (uint q = 1; q + 1 < poly.length; q++)
                triIndices ~= [poly[0], poly[q], poly[q + 1]];
    }

    GeometryVertex[] vertices;
    int[] indices;
    float[3] defaultNormal = [0.0f, 1.0f, 0.0f];
    float[3] defaultUv = [0.0f, 0.0f, 0.0f];
    for (size_t t = 0; t < triIndices.length; t += 3)
    {
        for (uint c = 0; c < 3; c++)
        {
            int cpIdx = triIndices[t + c];
            GeometryVertex v;
            v.pos[0] = controlPoints[cpIdx][0];
            v.pos[1] = -controlPoints[cpIdx][1];
            v.pos[2] = controlPoints[cpIdx][2];
            if (normals.length > 0 && (t + c) < normals.length)
            {
                v.normal[0] = normals[t + c][0];
                v.normal[1] = -normals[t + c][1];
                v.normal[2] = normals[t + c][2];
            }
            else
                v.normal = defaultNormal;
            if (uvs.length > 0 && (t + c) < uvs.length)
                v.texCoord = [uvs[t + c][0], 1.0f - uvs[t + c][1], 0.0f];
            else
                v.texCoord = defaultUv;
            v.color = [1.0f, 1.0f, 1.0f];
            vertices ~= v;
            indices ~= cast(int)(vertices.length - 1);
        }
    }

    debug (FbxLoader) writeln("FBX loaded: ", vertices.length, " vertices, ", indices.length, " indices");
    return tuple(vertices, indices);
}

private float[][] parseFbxFloat3Array(string line, string prefix)
{
    float[][] result;
    string rest = line.strip();
    if (rest.length <= prefix.length)
        return result;
    rest = rest[prefix.length .. $].strip();
    if (rest.startsWith("*"))
    {
        size_t br = rest.indexOf("{");
        if (br == -1)
            return result;
        rest = rest[br + 1 .. $];
        size_t end = rest.indexOf("}");
        if (end != -1)
            rest = rest[0 .. end];
    }
    string[] parts = rest.split(",");
    for (size_t i = 0; i + 2 < parts.length; i += 3)
    {
        float x = to!float(parts[i].strip());
        float y = to!float(parts[i + 1].strip());
        float z = to!float(parts[i + 2].strip());
        result ~= [[x, y, z]];
    }
    return result;
}

private float[][] parseFbxFloat3FromLine(string line, string prefix)
{
    float[][] result;
    string rest = line.strip();
    if (rest.length <= prefix.length)
        return result;
    rest = rest[prefix.length .. $].strip();
    if (rest.startsWith("*"))
    {
        size_t br = rest.indexOf("{");
        if (br != -1)
            rest = rest[br + 1 .. $];
        size_t end = rest.indexOf("}");
        if (end != -1)
            rest = rest[0 .. end];
    }
    string[] parts = rest.split(",");
    for (size_t i = 0; i + 2 < parts.length; i += 3)
    {
        float x = to!float(parts[i].strip());
        float y = to!float(parts[i + 1].strip());
        float z = to!float(parts[i + 2].strip());
        result ~= [[x, y, z]];
    }
    return result;
}

private float[][] parseFbxFloat2FromLine(string line, string prefix)
{
    float[][] result;
    string rest = line.strip();
    if (rest.length <= prefix.length)
        return result;
    rest = rest[prefix.length .. $].strip();
    if (rest.startsWith("*"))
    {
        size_t br = rest.indexOf("{");
        if (br != -1)
            rest = rest[br + 1 .. $];
        size_t end = rest.indexOf("}");
        if (end != -1)
            rest = rest[0 .. end];
    }
    string[] parts = rest.split(",");
    for (size_t i = 0; i + 1 < parts.length; i += 2)
    {
        float u = to!float(parts[i].strip());
        float v = to!float(parts[i + 1].strip());
        result ~= [[u, v]];
    }
    return result;
}

private int[] parseFbxIntArray(string line, string prefix)
{
    int[] result;
    string rest = line.strip();
    if (rest.length <= prefix.length)
        return result;
    rest = rest[prefix.length .. $].strip();
    if (rest.startsWith("*"))
    {
        size_t br = rest.indexOf("{");
        if (br != -1)
            rest = rest[br + 1 .. $];
        size_t end = rest.indexOf("}");
        if (end != -1)
            rest = rest[0 .. end];
    }
    string[] parts = rest.split(",");
    foreach (p; parts)
        result ~= to!int(p.strip());
    return result;
}
