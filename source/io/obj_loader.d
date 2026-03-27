module io.obj_loader;

import std.conv : to;
import std.file : readText;
import std.format : formattedRead;
import std.stdio;
import std.string;
import std.typecons : Tuple, tuple;

import model.geometry : GeometryVertex;

private struct ObjFace
{
    uint[3] v, t, n;

    this(uint v1, uint v2, uint v3,
         uint t1, uint t2, uint t3,
         uint n1, uint n2, uint n3)
    {
        v[0] = v1;
        v[1] = v2;
        v[2] = v3;
        t[0] = t1;
        t[1] = t2;
        t[2] = t3;
        n[0] = n1;
        n[1] = n2;
        n[2] = n3;
    }
}

/** Parse one OBJ face corner: `v`, `v/t`, `v//n`, or `v/t/n` (1-based indices as in the file). */
private void parseFaceCorner(string part, out uint vi, out uint ti, out uint ni)
{
    vi = ti = ni = 0;
    auto segs = part.split('/');
    assert(segs.length > 0 && segs[0].length);
    vi = segs[0].to!uint;
    if (segs.length >= 2 && segs[1].length)
        ti = segs[1].to!uint;
    if (segs.length >= 3 && segs[2].length)
        ni = segs[2].to!uint;
}

Tuple!(GeometryVertex[], int[]) loadObj(in string filename)
{
    debug (ObjectLoader) writeln("Loading model from: ", filename);

    uint numVerts = 0;
    uint numNormals = 0;
    uint numTexcoords = 0;
    uint numFaces = 0;

    string[] allLines = splitLines(readText(filename));

    foreach (line; allLines)
    {
        if (line.startsWith("v "))
            numVerts++;
        else if (line.startsWith("vn "))
            numNormals++;
        else if (line.startsWith("vt "))
            numTexcoords++;
        else if (line.startsWith("f "))
            numFaces++;
        else if (line.startsWith("g "))
        {
            debug (ObjectLoader) writeln("Warning: OBJ file \"", filename,
                    "\" contains groups, but we currently can't handle such files");
        }
        else if (line.startsWith("mtllib "))
        {
            debug (ObjectLoader) writeln("Warning: OBJ file \"", filename,
                    "\" contains materials, but we currently don't support them");
            debug (ObjectLoader) writeln("Material is in file: ", line[7 .. $]);
        }
    }

    debug (ObjectLoader) writeln("Model contains ", numVerts, " vertices, ", numNormals,
            " normals, ", numTexcoords, " texture coordinates, and ", numFaces, " faces");

    GeometryVertex[] tmpVertices;
    float[3][] tmpNormals;
    float[3][] tmpTexcoords;
    ObjFace[] tmpFaces;

    if (!numVerts)
        debug (ObjectLoader) writeln("Warning: OBJ file \"", filename, "\" has no vertices");
    if (!numNormals)
    {
        debug (ObjectLoader) writeln("Warning: OBJ file \"", filename,
                "\" has no normals (they will be generated)");
        numNormals = numVerts;
    }
    if (!numTexcoords)
    {
        debug (ObjectLoader) writeln("Warning: OBJ file \"", filename, "\" has no texcoords");
        numTexcoords = numVerts;
    }

    if (numVerts)
        tmpVertices.length = numVerts;
    if (numNormals)
        tmpNormals.length = numNormals;
    if (numTexcoords)
        tmpTexcoords.length = numTexcoords;

    float x, y, z, vt_x, vt_y, vt_z;
    uint v1, v2, v3, v4;
    uint t1, t2, t3, t4;
    uint n1, n2, n3, n4;
    uint vi = 0;
    uint ni = 0;
    uint ti = 0;

    foreach (line; allLines)
    {
        if (line.startsWith("v "))
        {
            debug (ObjectLoader_Details) writeln("Reading vertices ...");
            if (formattedRead(line, "v %s %s %s", &x, &y, &z))
            {
                debug (ObjectLoader_Details) writeln("Found vertex: ", x, " ", y, " ", z);
                tmpVertices[vi].pos = [x, -y, z];
                vi++;
            }
        }
        else if (line.startsWith("vn"))
        {
            if (formattedRead(line, "vn %s %s %s", &x, &y, &z))
            {
                debug (ObjectLoader_Details) writeln("Found Normal: ", x, " ", y, " ", z);
                tmpNormals[ni] = [x, -y, z];
                ni++;
            }
        }
        else if (line.startsWith("vt"))
        {
            if (formattedRead(line, "vt %s %s", &vt_x, &vt_y))
            {
                debug (ObjectLoader_Details) writeln("Found 2 Texture Coords: ", vt_x, " ", 1 - vt_y);
                tmpTexcoords[ti] = [vt_x, 1 - vt_y, 0];
                ti++;
            }
            else if (formattedRead(line, "vt %s %s %s", &vt_x, &vt_y, &vt_z))
            {
                debug (ObjectLoader_Details) writeln("Found 3 Texture Coords: ", vt_x, " ", vt_y, " ", vt_z);
                tmpTexcoords[ti] = [vt_x, 1 - vt_y, vt_z];
                ti++;
            }
            else
            {
                debug (Texture) writeln("Error: Invalid texture coordinate format");
                assert(0);
            }
        }
        else if (line.startsWith("vp"))
        {
        }
        else if (line.startsWith("f"))
        {
            debug (ObjectLoader_Details) writeln("Reading faces ...");
            // Pure D parsing (no sscanf): Bionic lacks glibc __isoc99_sscanf.
            string[] parts = line.strip().split();
            assert(parts.length >= 2);
            assert(parts[0] == "f");
            parts = parts[1 .. $];

            ObjFace face;

            if (parts.length == 4)
            {
                parseFaceCorner(parts[0], v1, t1, n1);
                parseFaceCorner(parts[1], v2, t2, n2);
                parseFaceCorner(parts[2], v3, t3, n3);
                parseFaceCorner(parts[3], v4, t4, n4);
                if (t1 && t2 && t3 && t4 && n1 && n2 && n3 && n4)
                {
                    debug (ObjectLoader_Details) writeln("Found face 001");
                    face = ObjFace(v1 - 1, v2 - 1, v3 - 1, t1 - 1, t2 - 1, t3 - 1, n1 - 1, n2 - 1, n3 - 1);
                    tmpFaces ~= face;
                    face = ObjFace(v1 - 1, v3 - 1, v4 - 1, t1 - 1, t3 - 1, t4 - 1, n1 - 1, n3 - 1, n4 - 1);
                    tmpFaces ~= face;
                }
                else if (n1 && n2 && n3 && n4 && !t1 && !t2 && !t3 && !t4)
                {
                    debug (ObjectLoader_Details) writeln("Found face 003");
                    face = ObjFace(v1 - 1, v2 - 1, v3 - 1, 0, 0, 0, n1 - 1, n2 - 1, n3 - 1);
                    tmpFaces ~= face;
                    face = ObjFace(v1 - 1, v3 - 1, v4 - 1, 0, 0, 0, n1 - 1, n3 - 1, n4 - 1);
                    tmpFaces ~= face;
                }
                else if (!t1 && !t2 && !t3 && !t4 && !n1 && !n2 && !n3 && !n4)
                {
                    debug (ObjectLoader_Details) writeln("Found face 006");
                    face = ObjFace(v1 - 1, v2 - 1, v3 - 1, 0, 0, 0, 0, 0, 0);
                    tmpFaces ~= face;
                    face = ObjFace(v1 - 1, v3 - 1, v4 - 1, 0, 0, 0, 0, 0, 0);
                    tmpFaces ~= face;
                }
                else
                    assert(0);
            }
            else if (parts.length == 3)
            {
                parseFaceCorner(parts[0], v1, t1, n1);
                parseFaceCorner(parts[1], v2, t2, n2);
                parseFaceCorner(parts[2], v3, t3, n3);
                if (t1 && t2 && t3 && n1 && n2 && n3)
                {
                    debug (ObjectLoader_Details) writeln("Found face 002");
                    face = ObjFace(v1 - 1, v2 - 1, v3 - 1, t1 - 1, t2 - 1, t3 - 1, n1 - 1, n2 - 1, n3 - 1);
                    tmpFaces ~= face;
                }
                else if (t1 && t2 && t3 && !n1 && !n2 && !n3)
                {
                    debug (ObjectLoader_Details) writeln("Found face 004");
                    face = ObjFace(v1 - 1, v2 - 1, v3 - 1, t1 - 1, t2 - 1, t3 - 1, 0, 0, 0);
                    tmpFaces ~= face;
                }
                else if (!t1 && !t2 && !t3 && n1 && n2 && n3)
                {
                    debug (ObjectLoader_Details) writeln("Found face 005");
                    face = ObjFace(v1 - 1, v2 - 1, v3 - 1, 0, 0, 0, n1 - 1, n2 - 1, n3 - 1);
                    tmpFaces ~= face;
                }
                else if (!t1 && !t2 && !t3 && !n1 && !n2 && !n3)
                {
                    debug (ObjectLoader_Details) writeln("Found face 007");
                    face = ObjFace(v1 - 1, v2 - 1, v3 - 1, 0, 0, 0, 0, 0, 0);
                    tmpFaces ~= face;
                }
                else
                    assert(0);
            }
            else
                assert(0);
        }
    }
    debug (ObjectLoader) writeln("tmpFaces.length: ", tmpFaces.length);

    GeometryVertex[] meshVertices;
    int[] meshIndices;
    meshVertices.reserve(tmpFaces.length * 3);
    meshIndices.reserve(tmpFaces.length * 3);

    uint index = 0;
    foreach (ref ObjFace f; tmpFaces)
    {
        foreach (int j; 0 .. f.v.length)
        {
            debug (ObjectLoader_Details) writeln("Vertex: ", j);
            GeometryVertex gv;
            gv.pos = tmpVertices[f.v[j]].pos;
            gv.normal = tmpNormals[f.n[j]];
            gv.texCoord = tmpTexcoords[f.t[j]];
            gv.color = [1.0f, 1.0f, 1.0f];
            meshVertices ~= gv;
            meshIndices ~= cast(int) index;
            index++;
        }
    }

    return tuple(meshVertices, meshIndices);
}
