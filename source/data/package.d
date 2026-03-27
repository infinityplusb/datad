/**
 * Shared data loading and canonical plotting model for IDA apps.
 *
 * Submodules: geometry (mesh vertices), paths, format detection, OBJ/FBX, FITS, CSV helpers,
 * `ida.data.plot` and `ida.data.ingest` for plottable entities.
 */
module datad;

public 
{
    import base_data;
    import geometry;
    import paths;
    import data_format;
    import obj_loader;
    import fbx;
    import fits;
    import csv_reader;
    import quat_math;
    import plot;
    import ingest;
    import ingest_horizons;
}