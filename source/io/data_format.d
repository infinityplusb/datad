module data_format;

import std.path : extension;
import std.string : toLower;
import std.typecons : Tuple;

import geometry : GeometryVertex;
import obj_loader : loadObj;
import fbx : loadFbx;

enum DataFileFormat
{
    unknown,
    obj,
    fbx,
    csv,
    fits,
    scene,
    txt,
    png,
}

DataFileFormat detectFormat(string path)
{
    string ext = extension(path).toLower();
    switch (ext)
    {
        case ".obj":
            return DataFileFormat.obj;
        case ".fbx":
            return DataFileFormat.fbx;
        case ".csv":
            return DataFileFormat.csv;
        case ".fits", ".fit":
            return DataFileFormat.fits;
        case ".scene":
            return DataFileFormat.scene;
        case ".txt":
            return DataFileFormat.txt;
        case ".png":
            return DataFileFormat.png;
        default:
            return DataFileFormat.unknown;
    }
}

/** Load triangulated mesh geometry from a path; supports .obj and .fbx. Path must already be OS-resolved if needed. */
Tuple!(GeometryVertex[], int[]) loadMeshByPath(string path)
{
    final switch (detectFormat(path))
    {
        case DataFileFormat.obj:
            return loadObj(path);
        case DataFileFormat.fbx:
            return loadFbx(path);
        case DataFileFormat.csv:
        case DataFileFormat.fits:
        case DataFileFormat.scene:
        case DataFileFormat.txt:
        case DataFileFormat.png:
        case DataFileFormat.unknown:
            throw new Exception("Not a supported mesh format: " ~ path);
    }
}
