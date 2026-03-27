/** Parse JPL Horizons vector ephemeris text into plottable entities. */
module ingest.horizons;

import std.conv;
import std.string;

import model.plot;

private struct HorizonsBody
{
    float x, y, z, vx, vy, vz;
    string name;
}

PlotIngestResult ingestHorizonsEphemerisText(string response)
{
    PlotIngestResult res;
    HorizonsBody[] objects;
    string[] lines = splitLines(response);
    bool inDataSection;
    bool foundHeader;
    bool parsedFirstPoint;
    bool headerSeenBeforeSOE;
    string currentObjectName;
    int objectIndex;

    foreach (line; lines)
    {
        string lineStr = line.strip();
        if (lineStr.indexOf("Target body name:") >= 0 || lineStr.indexOf("Revised:") >= 0)
        {
            string[] parts = lineStr.split(":");
            if (parts.length > 1)
                currentObjectName = parts[1].strip();
        }
        if (!inDataSection && lineStr.indexOf("X") >= 0 && lineStr.indexOf("Y") >= 0 && lineStr.indexOf("Z") >= 0
                && lineStr.indexOf("VX") < 0 && lineStr.indexOf("VY") < 0 && lineStr.length < 30)
        {
            headerSeenBeforeSOE = true;
            continue;
        }
        if (lineStr == "$$SOE")
        {
            inDataSection = true;
            foundHeader = headerSeenBeforeSOE;
            parsedFirstPoint = false;
            headerSeenBeforeSOE = false;
            continue;
        }
        if (lineStr == "$$EOE")
        {
            inDataSection = false;
            parsedFirstPoint = false;
            objectIndex++;
            continue;
        }
        if (inDataSection && !foundHeader && lineStr.indexOf("JDTDB") >= 0)
            continue;
        if (inDataSection && !foundHeader && lineStr.indexOf("X") >= 0 && lineStr.indexOf("Y") >= 0
                && lineStr.indexOf("Z") >= 0 && (lineStr.indexOf("VX") < 0 && lineStr.indexOf("VY") < 0))
        {
            foundHeader = true;
            continue;
        }
        if (inDataSection && foundHeader && lineStr.length > 0)
        {
            if (lineStr.length == 0 || lineStr[0] == '#' || lineStr[0] == '*' || lineStr.startsWith("$$"))
                continue;
            if (lineStr.indexOf("TDB") >= 0 && lineStr.indexOf("=") >= 0)
                continue;

            if (!parsedFirstPoint && (lineStr.indexOf(" X =") >= 0 || (lineStr.indexOf("X =") >= 0 && lineStr.indexOf("Y") >= 0)))
            {
                HorizonsBody obj;
                obj.name = currentObjectName.length > 0 ? currentObjectName : ("Object_" ~ to!string(objectIndex));
                try
                {
                    long xPosLong = lineStr.indexOf("X =");
                    if (xPosLong < 0)
                        xPosLong = lineStr.indexOf(" X =");
                    if (xPosLong >= 0)
                    {
                        int xPos = cast(int) xPosLong;
                        int xStart = xPos + 3;
                        long xEndLong = lineStr.indexOf(" Y", xStart);
                        if (xEndLong < 0)
                            xEndLong = lineStr.indexOf("Y", xStart);
                        if (xEndLong < 0)
                            xEndLong = lineStr.length;
                        obj.x = to!float(lineStr[xStart .. cast(int) xEndLong].strip());
                    }
                    long yPosLong = lineStr.indexOf("Y =");
                    if (yPosLong < 0)
                        yPosLong = lineStr.indexOf(" Y =");
                    if (yPosLong < 0)
                        yPosLong = lineStr.indexOf("Y=");
                    if (yPosLong < 0)
                        yPosLong = lineStr.indexOf(" Y=");
                    if (yPosLong >= 0)
                    {
                        int yPos = cast(int) yPosLong;
                        int yStart = yPos + (lineStr[yPos + 1] == '=' ? 2 : 3);
                        long yEndLong = lineStr.indexOf(" Z", yStart);
                        if (yEndLong < 0)
                            yEndLong = lineStr.indexOf("Z", yStart);
                        if (yEndLong < 0)
                            yEndLong = lineStr.length;
                        obj.y = to!float(lineStr[yStart .. cast(int) yEndLong].strip());
                    }
                    long zPosLong = lineStr.indexOf("Z =");
                    if (zPosLong < 0)
                        zPosLong = lineStr.indexOf(" Z =");
                    if (zPosLong < 0)
                        zPosLong = lineStr.indexOf("Z=");
                    if (zPosLong < 0)
                        zPosLong = lineStr.indexOf(" Z=");
                    if (zPosLong >= 0)
                    {
                        int zPos = cast(int) zPosLong;
                        int zStart = zPos + (lineStr[zPos + 1] == '=' ? 2 : 3);
                        obj.z = to!float(lineStr[zStart .. cast(int) lineStr.length].strip());
                    }
                    if (obj.x != 0.0f || obj.y != 0.0f || obj.z != 0.0f)
                    {
                        objects ~= obj;
                        parsedFirstPoint = true;
                    }
                }
                catch (Exception)
                {
                    continue;
                }
            }
            else if (lineStr.indexOf("VX=") >= 0 || lineStr.indexOf(" VX=") >= 0)
            {
                if (objects.length > 0)
                {
                    try
                    {
                        size_t li = objects.length - 1;
                        long vxPosLong = lineStr.indexOf("VX=");
                        if (vxPosLong >= 0)
                        {
                            int vxStart = cast(int) vxPosLong + 3;
                            long vxEndLong = lineStr.indexOf(" VY", vxStart);
                            if (vxEndLong < 0)
                                vxEndLong = lineStr.indexOf("VY", vxStart);
                            if (vxEndLong < 0)
                                vxEndLong = lineStr.length;
                            objects[li].vx = to!float(lineStr[vxStart .. cast(int) vxEndLong].strip());
                        }
                        long vyPosLong = lineStr.indexOf("VY=");
                        if (vyPosLong >= 0)
                        {
                            int vyStart = cast(int) vyPosLong + 3;
                            long vyEndLong = lineStr.indexOf(" VZ", vyStart);
                            if (vyEndLong < 0)
                                vyEndLong = lineStr.indexOf("VZ", vyStart);
                            if (vyEndLong < 0)
                                vyEndLong = lineStr.length;
                            objects[li].vy = to!float(lineStr[vyStart .. cast(int) vyEndLong].strip());
                        }
                        long vzPosLong = lineStr.indexOf("VZ=");
                        if (vzPosLong >= 0)
                        {
                            int vzStart = cast(int) vzPosLong + 3;
                            objects[li].vz = to!float(lineStr[vzStart .. cast(int) lineStr.length].strip());
                        }
                    }
                    catch (Exception)
                    {
                    }
                }
            }
        }
    }

    if (objects.length == 0)
        return res;
    float xMin = float.max, xMax = -float.max, yMin = float.max, yMax = -float.max, zMin = float.max, zMax = -float.max;
    foreach (obj; objects)
    {
        if (obj.x < xMin)
            xMin = obj.x;
        if (obj.x > xMax)
            xMax = obj.x;
        if (obj.y < yMin)
            yMin = obj.y;
        if (obj.y > yMax)
            yMax = obj.y;
        if (obj.z < zMin)
            zMin = obj.z;
        if (obj.z > zMax)
            zMax = obj.z;
    }
    float xRange = (xMax - xMin) > 0 ? (xMax - xMin) : 1.0f;
    float yRange = (yMax - yMin) > 0 ? (yMax - yMin) : 1.0f;
    float zRange = (zMax - zMin) > 0 ? (zMax - zMin) : 1.0f;
    float scaleFactor = 1.0f;
    PlottableEntity[] list;
    foreach (i, obj; objects)
    {
        float x = obj.x * scaleFactor;
        float y = obj.y * scaleFactor;
        float z = obj.z * scaleFactor;
        float nx = (obj.x - xMin) / xRange;
        float ny = (obj.y - yMin) / yRange;
        float nz = (obj.z - zMin) / zRange;
        string objName = obj.name;
        if (objName == "Object")
            objName = "SSO_" ~ to!string(i);
        string[] attrs = [
            "SOURCE=HORIZONS", "ID=" ~ objName, "NAME=" ~ objName, "X=" ~ to!string(obj.x),
            "Y=" ~ to!string(obj.y), "Z=" ~ to!string(obj.z), "VX=" ~ to!string(obj.vx),
            "VY=" ~ to!string(obj.vy), "VZ=" ~ to!string(obj.vz), "X_AU=" ~ to!string(obj.x),
            "Y_AU=" ~ to!string(obj.y), "Z_AU=" ~ to!string(obj.z), "VARIABLE_COUNT=3",
            "NV_0=" ~ to!string(nx), "NV_1=" ~ to!string(ny), "NV_2=" ~ to!string(nz)
        ];
        PlottableEntity pe;
        pe.x = x;
        pe.y = y;
        pe.z = z;
        pe.vx = obj.vx;
        pe.vy = obj.vy;
        pe.vz = obj.vz;
        pe.scaleX = pe.scaleY = pe.scaleZ = 0.5f;
        pe.color = PlotColor(0.5f + (i % 3) * 0.2f, 0.5f + ((i + 1) % 3) * 0.2f, 0.5f + ((i + 2) % 3) * 0.2f, 1.0f);
        pe.attributes = attrs;
        list ~= pe;
    }
    res.entities = list;
    res.variableDisplay.valid = true;
    res.variableDisplay.nColumns = 3;
    res.variableDisplay.columnNames = ["X_AU", "Y_AU", "Z_AU"];
    res.variableDisplay.axisIndices = [0, 1, 2];
    res.variableDisplay.scale = 4.0f;
    return res;
}
