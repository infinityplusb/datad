module paths;

/** If androidAssetRoot is set and path is under data/, return root/path for on-device assets. */
string resolveDataPath(string path, string androidAssetRoot)
{
    if (androidAssetRoot.length && path.length >= 5 && path[0 .. 5] == "data/")
        return androidAssetRoot ~ "/" ~ path;
    return path;
}
