/**
 * Generic file → $(LINK2 plot.d, PlottableEntity) pipelines. Extend here with new strategies, not per-app loaders.
 */
module ingest;

import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.math;
import std.random;
import std.range : iota;
import std.stdio;
import std.string;
import std.process;

import csv_reader;
import fits;
import plot;

private string[] splitCsvLine(string ln)
{
    string[] res;
    size_t a = 0;
    foreach (i; 0 .. ln.length + 1)
    {
        if (i == ln.length || ln[i] == ',')
        {
            res ~= ln[a .. i].strip();
            a = i + 1;
        }
    }
    return res;
}

private bool isNumericToken(string s)
{
    if (s.strip().length == 0)
        return false;
    try
    {
        to!double(s.strip());
        return true;
    }
    catch (Exception)
    {
        return false;
    }
}

private int[] numericColumnIndices(string[] headers, string[] firstRow)
{
    int[] indices;
    foreach (i, h; headers)
    {
        if (i < firstRow.length && isNumericToken(firstRow[i]))
            indices ~= cast(int) i;
    }
    return indices;
}

private int[] pickRandomNumeric(string[] headers, string[] firstRow, int n)
{
    int[] all = numericColumnIndices(headers, firstRow);
    if (cast(size_t) n >= all.length)
        return all.dup;
    randomShuffle(all);
    return all[0 .. n].dup;
}

/** Three numeric columns for X,Y,Z; optional names (case-insensitive); if empty, pick three random numeric columns. */
PlotIngestResult ingestGenericTabular(string filePath, string xColName = "", string yColName = "",
        string zColName = "", size_t maxRows = 100_000)
{
    PlotIngestResult res;
    res.variableDisplay.valid = false;

    char delimiter = CSVReader.detectDelimiter(filePath);
    auto reader = new CSVReader(filePath, delimiter);
    string[] headers = reader.getHeaders();
    string[][] rows = reader.getRows();
    if (rows.length == 0)
        return res;

    int[] allNumeric = numericColumnIndices(headers, rows[0]);
    if (allNumeric.length < 3)
        return res;

    int xIdx = -1, yIdx = -1, zIdx = -1;
    if (xColName.length && yColName.length && zColName.length)
    {
        xIdx = reader.getColumnIndex(xColName);
        yIdx = reader.getColumnIndex(yColName);
        zIdx = reader.getColumnIndex(zColName);
        if (xIdx < 0 || yIdx < 0 || zIdx < 0)
            return res;
    }
    else
    {
        int[] picked = pickRandomNumeric(headers, rows[0], 3);
        xIdx = picked[0];
        yIdx = picked[1];
        zIdx = picked[2];
    }

    size_t total = rows.length;
    size_t stride = 1;
    if (total > maxRows)
        stride = (total + maxRows - 1) / maxRows;

    int nVar = cast(int) allNumeric.length;
    float[] colMin = new float[](nVar);
    float[] colMax = new float[](nVar);
    foreach (i; 0 .. nVar)
    {
        colMin[i] = float.max;
        colMax[i] = -float.max;
    }
    for (size_t i = 0; i < total; i += stride)
    {
        string[] row = rows[i];
        foreach (k, colIdx; allNumeric)
        {
            if (row.length <= colIdx)
                continue;
            try
            {
                float v = to!float(row[colIdx].strip());
                if (colMin[k] > v)
                    colMin[k] = v;
                if (colMax[k] < v)
                    colMax[k] = v;
            }
            catch (Exception)
            {
            }
        }
    }
    float[] colRange = new float[](nVar);
    foreach (k; 0 .. nVar)
        colRange[k] = (colMax[k] - colMin[k]) > 0 ? (colMax[k] - colMin[k]) : 1.0f;

    int xi = -1, yi = -1, zi = -1;
    foreach (k, idx; allNumeric)
    {
        if (idx == xIdx)
            xi = cast(int) k;
        if (idx == yIdx)
            yi = cast(int) k;
        if (idx == zIdx)
            zi = cast(int) k;
    }

    res.variableDisplay.valid = true;
    res.variableDisplay.nColumns = nVar;
    res.variableDisplay.scale = 4.0f;
    res.variableDisplay.columnNames = allNumeric.map!(i => headers[i]).array;
    res.variableDisplay.axisIndices = [xi >= 0 ? xi : 0, yi >= 0 ? yi : 1, zi >= 0 ? zi : 2];

    float scale = 4.0f;
    PlottableEntity[] list;
    for (size_t i = 0; i < total; i++)
    {
        if (i % stride != 0)
            continue;
        if (list.length >= maxRows)
            break;
        string[] row = rows[i];
        int maxCol = max(xIdx, max(yIdx, zIdx));
        foreach (idx; allNumeric)
            if (idx > maxCol)
                maxCol = idx;
        if (row.length <= maxCol)
            continue;
        float vx, vy, vz;
        try
        {
            vx = to!float(row[xIdx].strip());
            vy = to!float(row[yIdx].strip());
            vz = to!float(row[zIdx].strip());
        }
        catch (Exception)
        {
            continue;
        }
        int u = xi >= 0 ? xi : 0, v = yi >= 0 ? yi : 1, w = zi >= 0 ? zi : 2;
        float nx = (vx - colMin[u]) / colRange[u];
        float ny = (vy - colMin[v]) / colRange[v];
        float nz = (vz - colMin[w]) / colRange[w];
        float x = (nx - 0.5f) * scale;
        float y = ny * scale;
        float z = (nz - 0.5f) * scale;

        string[] attrs = ["SOURCE=CSV", "VARIABLE_COUNT=" ~ to!string(nVar),
            "POS_X=" ~ to!string(x), "POS_Y=" ~ to!string(y), "POS_Z=" ~ to!string(z)];
        foreach (k; 0 .. nVar)
        {
            try
            {
                float val = to!float(row[allNumeric[k]].strip());
                float nv = (val - colMin[k]) / colRange[k];
                attrs ~= "NV_" ~ to!string(k) ~ "=" ~ to!string(nv);
            }
            catch (Exception)
            {
                attrs ~= "NV_" ~ to!string(k) ~ "=0";
            }
        }
        foreach (j, h; headers)
        {
            if (j < row.length && h.length > 0)
                attrs ~= h ~ "=" ~ row[j].strip();
        }

        PlottableEntity pe;
        pe.x = x;
        pe.y = y;
        pe.z = z;
        pe.scaleX = pe.scaleY = pe.scaleZ = 0.06f;
        pe.color = PlotColor(0.2f + (list.length % 5) * 0.15f, 0.3f + (list.length % 7) * 0.1f,
                0.5f + (list.length % 4) * 0.12f, 1.0f);
        pe.attributes = attrs;
        list ~= pe;
    }
    res.entities = list;
    return res;
}

PlotIngestResult ingestOnlineRetail(string filePath, size_t maxRows = 100_000)
{
    PlotIngestResult res;
    char delimiter = CSVReader.detectDelimiter(filePath);
    auto reader = new CSVReader(filePath, delimiter);
    string[] headers = reader.getHeaders();
    string[][] rows = reader.getRows();
    int qtyIdx = reader.getColumnIndex("Quantity");
    int priceIdx = reader.getColumnIndex("Price");
    int invIdx = reader.getColumnIndex("Invoice");
    int stockIdx = reader.getColumnIndex("StockCode");
    int descIdx = reader.getColumnIndex("Description");
    int dateIdx = reader.getColumnIndex("InvoiceDate");
    int custIdx = reader.getColumnIndex("Customer ID");
    int countryIdx = reader.getColumnIndex("Country");
    if (qtyIdx < 0 || priceIdx < 0)
        return res;

    size_t total = rows.length;
    size_t stride = 1;
    if (total > maxRows)
        stride = (total + maxRows - 1) / maxRows;
    float qtyMin = float.max, qtyMax = -float.max, priceMin = float.max, priceMax = -float.max;
    for (size_t i = 0; i < total; i += stride)
    {
        string[] row = rows[i];
        if (qtyIdx < row.length && priceIdx < row.length)
        {
            try
            {
                float q = to!float(row[qtyIdx].strip()), p = to!float(row[priceIdx].strip());
                if (qtyMin > q)
                    qtyMin = q;
                if (qtyMax < q)
                    qtyMax = q;
                if (priceMin > p)
                    priceMin = p;
                if (priceMax < p)
                    priceMax = p;
            }
            catch (Exception)
            {
            }
        }
    }
    float qtyRange = (qtyMax - qtyMin) > 0 ? (qtyMax - qtyMin) : 1.0f;
    float priceRange = (priceMax - priceMin) > 0 ? (priceMax - priceMin) : 1.0f;
    float scaleX = 2.0f, scaleY = 4.0f, scaleZ = 4.0f;
    PlottableEntity[] list;
    size_t countSpawned;
    for (size_t i = 0; i < total; i++)
    {
        if (i % stride != 0)
            continue;
        if (countSpawned >= maxRows)
            break;
        string[] row = rows[i];
        if (row.length <= max(qtyIdx, priceIdx))
            continue;
        float quantity, price;
        try
        {
            quantity = to!float(row[qtyIdx].strip());
            price = to!float(row[priceIdx].strip());
        }
        catch (Exception)
        {
            continue;
        }
        float nq = (quantity - qtyMin) / qtyRange;
        float np = (price - priceMin) / priceRange;
        float x = (countSpawned % 200) * (scaleX / 50.0f) - scaleX * 0.5f;
        float y = nq * scaleY;
        float z = np * scaleZ;
        string invoice = invIdx >= 0 && invIdx < row.length ? row[invIdx].strip() : "";
        string stockCode = stockIdx >= 0 && stockIdx < row.length ? row[stockIdx].strip() : "";
        string description = descIdx >= 0 && descIdx < row.length ? row[descIdx].strip() : "";
        string invoiceDate = dateIdx >= 0 && dateIdx < row.length ? row[dateIdx].strip() : "";
        string customerId = custIdx >= 0 && custIdx < row.length ? row[custIdx].strip() : "";
        string country = countryIdx >= 0 && countryIdx < row.length ? row[countryIdx].strip() : "";
        float ni = total > 1 ? cast(float) i / cast(float)(total - 1) : 0.5f;
        string[] attrs = [
            "SOURCE=ONLINE_RETAIL", "Invoice=" ~ invoice, "StockCode=" ~ stockCode,
            "Description=" ~ description, "Quantity=" ~ to!string(quantity),
            "InvoiceDate=" ~ invoiceDate, "Price=" ~ to!string(price),
            "Customer ID=" ~ customerId, "Country=" ~ country, "VARIABLE_COUNT=3",
            "NV_0=" ~ to!string(nq), "NV_1=" ~ to!string(np), "NV_2=" ~ to!string(ni)
        ];
        PlottableEntity pe;
        pe.x = x;
        pe.y = y;
        pe.z = z;
        pe.scaleX = pe.scaleY = pe.scaleZ = 0.08f;
        pe.color = PlotColor(0.3f + (countSpawned % 5) * 0.15f, 0.4f + (countSpawned % 7) * 0.08f,
                0.6f + (countSpawned % 3) * 0.13f, 1.0f);
        pe.attributes = attrs;
        list ~= pe;
        countSpawned++;
    }
    res.entities = list;
    res.variableDisplay.valid = true;
    res.variableDisplay.nColumns = 3;
    res.variableDisplay.columnNames = ["Quantity", "Price", "RowIndex"];
    res.variableDisplay.axisIndices = [0, 1, 2];
    res.variableDisplay.scale = 4.0f;
    return res;
}

private void raDecParallaxToXYZ(float raDeg, float decDeg, float parallaxMas,
        out float x, out float y, out float z, out float distance)
{
    enum PI = 3.14159265358979323846L;
    float raRad = raDeg * (cast(float) PI / 180.0f);
    float decRad = decDeg * (cast(float) PI / 180.0f);
    if (parallaxMas <= 0 || parallaxMas < 0.1f)
        distance = 100.0f;
    else
        distance = 1000.0f / parallaxMas;
    x = distance * cos(decRad) * cos(raRad);
    y = distance * cos(decRad) * sin(raRad);
    z = distance * sin(decRad);
}

PlotIngestResult ingestStarCatalogueCsv(string filePath, size_t maxStars = 100_000)
{
    PlotIngestResult res;
    auto csv = new CSVReader(filePath);
    string[] headers = csv.getHeaders();
    string[][] rows = csv.getRows();
    int raIdx = csv.getColumnIndex("ra");
    if (raIdx < 0)
        raIdx = csv.getColumnIndex("right_ascension");
    if (raIdx < 0)
        raIdx = csv.getColumnIndex("RA");
    int decIdx = csv.getColumnIndex("dec");
    if (decIdx < 0)
        decIdx = csv.getColumnIndex("declination");
    if (decIdx < 0)
        decIdx = csv.getColumnIndex("Dec");
    int plxIdx = csv.getColumnIndex("parallax");
    if (plxIdx < 0)
        plxIdx = csv.getColumnIndex("plx");
    if (plxIdx < 0)
        plxIdx = csv.getColumnIndex("parallax_mas");
    if (plxIdx < 0)
        plxIdx = csv.getColumnIndex("Parallax");
    int magIdx = csv.getColumnIndex("magnitude");
    if (magIdx < 0)
        magIdx = csv.getColumnIndex("mag");
    if (magIdx < 0)
        magIdx = csv.getColumnIndex("vmag");
    if (magIdx < 0)
        magIdx = csv.getColumnIndex("apparent_magnitude");
    int idIdx = csv.getColumnIndex("id");
    if (idIdx < 0)
        idIdx = csv.getColumnIndex("source_id");
    if (idIdx < 0)
        idIdx = csv.getColumnIndex("hip");
    if (idIdx < 0)
        idIdx = csv.getColumnIndex("tyc");
    if (raIdx < 0 || decIdx < 0)
        return res;

    size_t stride = 1;
    if (rows.length > maxStars)
        stride = (rows.length + maxStars - 1) / maxStars;
    float scaleFactor = 0.1f;
    PlottableEntity[] list;
    foreach (i; 0 .. rows.length)
    {
        if (i % stride != 0)
            continue;
        if (list.length >= maxStars)
            break;
        string[] row = rows[i];
        if (raIdx >= row.length || decIdx >= row.length)
            continue;
        float ra, dec;
        try
        {
            ra = to!float(row[raIdx]);
            dec = to!float(row[decIdx]);
        }
        catch (Exception)
        {
            continue;
        }
        float parallax = 0.0f;
        if (plxIdx >= 0 && plxIdx < row.length && row[plxIdx].length > 0)
        {
            try
                parallax = to!float(row[plxIdx]);
            catch (Exception)
            {
            }
        }
        float magnitude = 0.0f;
        if (magIdx >= 0 && magIdx < row.length && row[magIdx].length > 0)
        {
            try
                magnitude = to!float(row[magIdx]);
            catch (Exception)
            {
            }
        }
        string id = idIdx >= 0 && idIdx < row.length ? row[idIdx] : ("STAR_" ~ to!string(i));
        float cx, cy, cz, dist;
        raDecParallaxToXYZ(ra, dec, parallax, cx, cy, cz, dist);
        float sx = cx * scaleFactor, sy = cy * scaleFactor, sz = cz * scaleFactor;
        float nra = (ra % 360.0f + 360.0f) % 360.0f / 360.0f;
        float ndec = (dec + 90.0f) / 180.0f;
        float distNorm = dist > 0 ? (dist < 500.0f ? dist / 500.0f : 1.0f) : 0.0f;
        string[] attrs = [
            "SOURCE=STAR_CATALOGUE", "ID=" ~ id, "RA=" ~ to!string(ra), "DEC=" ~ to!string(dec),
            "PARALLAX=" ~ to!string(parallax), "DISTANCE=" ~ to!string(dist),
            "MAGNITUDE=" ~ to!string(magnitude), "VARIABLE_COUNT=3",
            "NV_0=" ~ to!string(nra), "NV_1=" ~ to!string(ndec), "NV_2=" ~ to!string(distNorm)
        ];
        float starSize = 0.1f;
        if (magnitude > 0)
        {
            starSize = 0.2f / (1.0f + magnitude * 0.1f);
            if (starSize < 0.05f)
                starSize = 0.05f;
            if (starSize > 0.5f)
                starSize = 0.5f;
        }
        float brightness = 1.0f / (1.0f + magnitude * 0.2f);
        if (brightness > 1.0f)
            brightness = 1.0f;
        PlottableEntity pe;
        pe.x = sx;
        pe.y = sy;
        pe.z = sz;
        pe.scaleX = pe.scaleY = pe.scaleZ = starSize;
        pe.color = PlotColor(1.0f, 0.8f + brightness * 0.2f, 0.6f + brightness * 0.4f, 1.0f);
        pe.attributes = attrs;
        list ~= pe;
    }
    res.entities = list;
    res.variableDisplay.valid = true;
    res.variableDisplay.nColumns = 3;
    res.variableDisplay.columnNames = ["RA", "Dec", "Distance"];
    res.variableDisplay.axisIndices = [0, 1, 2];
    res.variableDisplay.scale = 4.0f;
    return res;
}

private float parseRATycho(string raStr)
{
    raStr = raStr.strip();
    string[] parts = raStr.split();
    if (parts.length < 3)
        return 0.0f;
    try
    {
        float hours = to!float(parts[0]), minutes = to!float(parts[1]), seconds = to!float(parts[2]);
        return (hours + minutes / 60.0f + seconds / 3600.0f) * 15.0f;
    }
    catch (Exception)
    {
        return 0.0f;
    }
}

private float parseDecTycho(string decStr)
{
    decStr = decStr.strip();
    bool negative = false;
    if (decStr.length > 0 && decStr[0] == '-')
    {
        negative = true;
        decStr = decStr[1 .. $];
    }
    else if (decStr.length > 0 && decStr[0] == '+')
        decStr = decStr[1 .. $];
    string[] parts = decStr.split();
    if (parts.length < 3)
        return 0.0f;
    try
    {
        float degrees = to!float(parts[0]), minutes = to!float(parts[1]), seconds = to!float(parts[2]);
        float decDegrees = degrees + minutes / 60.0f + seconds / 3600.0f;
        return negative ? -decDegrees : decDegrees;
    }
    catch (Exception)
    {
        return 0.0f;
    }
}

private struct Tycho2StarRec
{
    string tycId, id;
    float ra, dec, vtMag, btMag, pmRA, pmDec;
}

private Tycho2StarRec parseTycho2LineStr(string line)
{
    Tycho2StarRec star;
    string[] fields = line.split("|");
    if (fields.length < 9)
        return star;
    if (fields.length > 1)
    {
        star.tycId = fields[1].strip();
        star.id = "TYC" ~ replace(star.tycId, " ", "-");
    }
    bool raParsed, decParsed;
    string raDecimal = fields.length > 8 ? fields[8].strip : "";
    if (raDecimal.length == 0 && fields.length > 7)
        raDecimal = fields[7].strip;
    if (raDecimal.length > 0)
    {
        try
        {
            star.ra = to!float(raDecimal);
            raParsed = true;
        }
        catch (Exception)
        {
        }
    }
    if (!raParsed)
    {
        string raSex = fields.length > 3 ? fields[3].strip : "";
        if (raSex.length == 0 && fields.length > 2)
            raSex = fields[2].strip;
        if (raSex.length > 0 && raSex.split().length >= 3)
        {
            star.ra = parseRATycho(raSex);
            raParsed = true;
        }
    }
    string decDecimal = fields.length > 9 ? fields[9].strip : "";
    if (decDecimal.length == 0 && fields.length > 8)
        decDecimal = fields[8].strip;
    if (decDecimal.length > 0)
    {
        try
        {
            star.dec = to!float(decDecimal);
            decParsed = true;
        }
        catch (Exception)
        {
        }
    }
    if (!decParsed)
    {
        string decSex = fields.length > 4 ? fields[4].strip : "";
        if (decSex.length == 0 && fields.length > 3)
            decSex = fields[3].strip;
        if (decSex.length > 0 && decSex.split().length >= 3)
        {
            star.dec = parseDecTycho(decSex);
            decParsed = true;
        }
    }
    if (fields.length > 31)
    {
        try
        {
            string vtField = fields[31].strip;
            if (vtField.length > 0)
                star.vtMag = to!float(vtField);
        }
        catch (Exception)
        {
        }
        if (fields.length > 33)
        {
            try
            {
                string btField = fields[33].strip;
                if (btField.length > 0)
                    star.btMag = to!float(btField);
            }
            catch (Exception)
            {
            }
        }
    }
    if (star.vtMag == 0.0f && fields.length > 4)
    {
        try
        {
            string magField = fields[4].strip;
            if (magField.length > 0)
                star.vtMag = to!float(magField);
        }
        catch (Exception)
        {
        }
    }
    if (fields.length > 10)
    {
        try
        {
            float pmRACosDec = to!float(fields[9].strip);
            star.pmDec = to!float(fields[10].strip);
            star.pmRA = pmRACosDec;
        }
        catch (Exception)
        {
        }
    }
    return star;
}

PlotIngestResult ingestTycho2Dat(string filePath, size_t maxStars = 1_000_000)
{
    PlotIngestResult res;
    enum PI = 3.14159265358979323846L;
    string[] lines = splitLines(readText(filePath));
    size_t totalLines = lines.length;
    size_t stride = 1;
    if (totalLines > maxStars)
        stride = (totalLines + maxStars - 1) / maxStars;
    float scaleFactor = 0.1f;
    PlottableEntity[] list;
    size_t lineNum;
    foreach (line; lines)
    {
        lineNum++;
        if (lineNum % stride != 0)
            continue;
        if (list.length >= maxStars)
            break;
        string lineStr = line;
        if (lineStr.strip().length == 0)
            continue;
        Tycho2StarRec star = parseTycho2LineStr(lineStr);
        if (star.ra == 0.0f && star.dec == 0.0f)
            continue;
        float magnitude = star.vtMag;
        if (magnitude == 0.0f)
            magnitude = star.btMag;
        if (magnitude == 0.0f)
            magnitude = 10.0f;
        float distVar1 = sin(star.ra * cast(float) PI / 180.0f * 7.0f) * 40.0f;
        float distVar2 = cos(star.dec * cast(float) PI / 180.0f * 5.0f) * 30.0f;
        float distVar3 = sin((star.ra + star.dec) * cast(float) PI / 180.0f * 3.0f) * 20.0f;
        float distance = 100.0f + distVar1 + distVar2 + distVar3;
        if (distance < 30.0f)
            distance = 30.0f;
        if (distance > 200.0f)
            distance = 200.0f;
        float raRad = star.ra * (cast(float) PI / 180.0f);
        float decRad = star.dec * (cast(float) PI / 180.0f);
        float x = distance * cos(decRad) * cos(raRad);
        float y = distance * cos(decRad) * sin(raRad);
        float z = distance * sin(decRad);
        float sx = x * scaleFactor, sy = y * scaleFactor, sz = z * scaleFactor;
        float nra = (star.ra % 360.0f + 360.0f) % 360.0f / 360.0f;
        float ndec = (star.dec + 90.0f) / 180.0f;
        float nmag = magnitude >= 0 && magnitude <= 15 ? magnitude / 15.0f : 0.5f;
        string[] attrs = [
            "SOURCE=TYCHO2", "ID=" ~ star.id, "TYC=" ~ star.tycId,
            "RA=" ~ to!string(star.ra), "DEC=" ~ to!string(star.dec),
            "VT_MAG=" ~ to!string(star.vtMag), "BT_MAG=" ~ to!string(star.btMag),
            "MAGNITUDE=" ~ to!string(magnitude),
            "PM_RA=" ~ to!string(star.pmRA), "PM_DEC=" ~ to!string(star.pmDec),
            "VARIABLE_COUNT=3", "NV_0=" ~ to!string(nra), "NV_1=" ~ to!string(ndec),
            "NV_2=" ~ to!string(nmag)
        ];
        float starSize = 0.1f;
        if (magnitude > 0)
        {
            starSize = 0.2f / (1.0f + magnitude * 0.1f);
            if (starSize < 0.05f)
                starSize = 0.05f;
            if (starSize > 0.5f)
                starSize = 0.5f;
        }
        float brightness = 1.0f / (1.0f + magnitude * 0.2f);
        if (brightness > 1.0f)
            brightness = 1.0f;
        PlottableEntity pe;
        pe.x = sx;
        pe.y = sy;
        pe.z = sz;
        pe.scaleX = pe.scaleY = pe.scaleZ = starSize;
        pe.color = PlotColor(1.0f, 0.8f + brightness * 0.2f, 0.6f + brightness * 0.4f, 1.0f);
        pe.attributes = attrs;
        list ~= pe;
    }
    res.entities = list;
    res.variableDisplay.valid = true;
    res.variableDisplay.nColumns = 3;
    res.variableDisplay.columnNames = ["RA", "Dec", "Magnitude"];
    res.variableDisplay.axisIndices = [0, 1, 2];
    res.variableDisplay.scale = 4.0f;
    return res;
}

private enum CovCol
{
    Elevation = 0,
    Aspect = 1,
    Slope = 2,
    Hillshade_Noon = 7,
    Cover_Type = 54,
    NCol = 55
}

PlotIngestResult ingestCovtype(string filePath, size_t maxRows = 100_000)
{
    PlotIngestResult res;
    string[][] rows;
    if (filePath.toLower().endsWith(".gz"))
    {
        auto p = pipeProcess(["gunzip", "-c", filePath]);
        scope (exit)
            wait(p.pid);
        string content;
        foreach (ubyte[] chunk; p.stdout.byChunk(4096))
            content ~= cast(char[]) chunk;
        foreach (ln; splitLines(content))
        {
            string[] fields = splitCsvLine(ln.idup);
            if (fields.length >= CovCol.NCol)
                rows ~= fields;
        }
    }
    else
    {
        foreach (ln; splitLines(readText(filePath)))
        {
            string[] fields = splitCsvLine(ln.idup);
            if (fields.length >= CovCol.NCol)
                rows ~= fields;
        }
    }
    if (rows.length == 0)
        return res;
    size_t stride = 1;
    if (rows.length > maxRows)
        stride = (rows.length + maxRows - 1) / maxRows;
    float elevMin = float.max, elevMax = -float.max, slopeMin = float.max, slopeMax = -float.max;
    float hillMin = float.max, hillMax = -float.max;
    for (size_t i = 0; i < rows.length; i += stride)
    {
        string[] row = rows[i];
        try
        {
            float e = to!float(row[cast(size_t) CovCol.Elevation]);
            float s = to!float(row[cast(size_t) CovCol.Slope]);
            float h = to!float(row[cast(size_t) CovCol.Hillshade_Noon]);
            if (elevMin > e)
                elevMin = e;
            if (elevMax < e)
                elevMax = e;
            if (slopeMin > s)
                slopeMin = s;
            if (slopeMax < s)
                slopeMax = s;
            if (hillMin > h)
                hillMin = h;
            if (hillMax < h)
                hillMax = h;
        }
        catch (Exception)
        {
        }
    }
    float elevRange = (elevMax - elevMin) > 0 ? (elevMax - elevMin) : 1.0f;
    float slopeRange = (slopeMax - slopeMin) > 0 ? (slopeMax - slopeMin) : 1.0f;
    float hillRange = (hillMax - hillMin) > 0 ? (hillMax - hillMin) : 1.0f;
    float scaleX = 4.0f, scaleY = 4.0f, scaleZ = 4.0f;
    PlottableEntity[] list;
    size_t countSpawned, skipped;
    for (size_t i = 0; i < rows.length; i++)
    {
        if (i % stride != 0)
        {
            skipped++;
            continue;
        }
        if (countSpawned >= maxRows)
            break;
        string[] row = rows[i];
        float elevation, aspect, slope, coverType;
        try
        {
            elevation = to!float(row[cast(size_t) CovCol.Elevation]);
            aspect = to!float(row[cast(size_t) CovCol.Aspect]);
            slope = to!float(row[cast(size_t) CovCol.Slope]);
            coverType = to!float(row[cast(size_t) CovCol.Cover_Type]);
        }
        catch (Exception)
        {
            skipped++;
            continue;
        }
        float hillNoon = 0;
        try
            hillNoon = to!float(row[cast(size_t) CovCol.Hillshade_Noon]);
        catch (Exception)
        {
        }
        float nx = (elevation - elevMin) / elevRange;
        float ny = (slope - slopeMin) / slopeRange;
        float nz = (hillNoon - hillMin) / hillRange;
        float x = (nx - 0.5f) * scaleX;
        float y = ny * scaleY;
        float z = (nz - 0.5f) * scaleZ;
        string[] attrs = [
            "SOURCE=COVTYPE", "Elevation=" ~ to!string(elevation), "Aspect=" ~ to!string(aspect),
            "Slope=" ~ to!string(slope), "Cover_Type=" ~ to!string(cast(int) coverType),
            "Hillshade_Noon=" ~ to!string(hillNoon), "VARIABLE_COUNT=3",
            "NV_0=" ~ to!string(nx), "NV_1=" ~ to!string(ny), "NV_2=" ~ to!string(nz)
        ];
        PlottableEntity pe;
        pe.x = x;
        pe.y = y;
        pe.z = z;
        pe.scaleX = pe.scaleY = pe.scaleZ = 0.04f;
        pe.color = PlotColor(0.2f + (cast(int) coverType - 1) * 0.12f,
                0.3f + (countSpawned % 4) * 0.15f, 0.5f + (countSpawned % 3) * 0.15f, 1.0f);
        pe.attributes = attrs;
        list ~= pe;
        countSpawned++;
    }
    res.entities = list;
    res.variableDisplay.valid = true;
    res.variableDisplay.nColumns = 3;
    res.variableDisplay.columnNames = ["Elevation", "Slope", "Hillshade_Noon"];
    res.variableDisplay.axisIndices = [0, 1, 2];
    res.variableDisplay.scale = 4.0f;
    return res;
}

/** One middle slice of a FITS image as cube markers (same layout as legacy server). */
PlotIngestResult ingestFitsMiddleSlice(string filePath, size_t maxDim = 1_000_000)
{
    PlotIngestResult res;
    auto ff = new FitsFile(filePath);
    if (ff.header.NAXIS < 2 || ff.data.values.length == 0)
        return res;
    size_t nx = cast(size_t) ff.header.NAXIS1;
    size_t ny = cast(size_t)(ff.header.NAXIS >= 2 ? ff.header.NAXIS2 : 1);
    size_t nz = cast(size_t)(ff.header.NAXIS >= 3 ? ff.header.NAXIS3 : 1);
    size_t layer = nz > 1 ? nz / 2 : 0;
    auto values = ff.data.values;
    size_t sliceOffset = layer * nx * ny;
    size_t strideX = nx > maxDim ? (nx + maxDim - 1) / maxDim : 1;
    size_t strideY = ny > maxDim ? (ny + maxDim - 1) / maxDim : 1;
    float vmin = float.max, vmax = -float.max;
    foreach (j; 0 .. ny)
        foreach (i; 0 .. nx)
        {
            auto v = values[sliceOffset + j * nx + i];
            if (v < vmin)
                vmin = v;
            if (v > vmax)
                vmax = v;
        }
    float vrange = (vmax - vmin) != 0 ? (vmax - vmin) : 1.0f;
    float iMax = cast(float)(nx > 1 ? nx - 1 : 1);
    float jMax = cast(float)(ny > 1 ? ny - 1 : 1);
    PlottableEntity[] list;
    foreach (j; iota(cast(size_t) 0, ny, strideY))
        foreach (i; iota(cast(size_t) 0, nx, strideX))
        {
            auto v = values[sliceOffset + j * nx + i];
            float norm = (v - vmin) / vrange;
            float nv0 = cast(float) i / iMax;
            float nv1 = cast(float) j / jMax;
            float gx = cast(float) i / cast(float) strideX;
            float gz = cast(float) j / cast(float) strideY;
            float x = gx * 1.2f;
            float z = gz * 1.2f;
            float y = norm * 2.0f;
            string[] attrs = [
                "SOURCE=FITS", "I=" ~ to!string(i), "J=" ~ to!string(j), "K=" ~ to!string(layer),
                "VALUE=" ~ to!string(v), "NORM=" ~ to!string(norm), "GX=" ~ to!string(gx),
                "GZ=" ~ to!string(gz), "NX=" ~ to!string(nx), "NY=" ~ to!string(ny),
                "NZ=" ~ to!string(nz), "STRIDEX=" ~ to!string(strideX),
                "STRIDEY=" ~ to!string(strideY), "VARIABLE_COUNT=3",
                "NV_0=" ~ to!string(nv0), "NV_1=" ~ to!string(nv1), "NV_2=" ~ to!string(norm)
            ];
            PlottableEntity pe;
            pe.x = x;
            pe.y = y;
            pe.z = z;
            pe.scaleX = pe.scaleY = pe.scaleZ = 0.9f;
            pe.attributes = attrs;
            list ~= pe;
        }
    res.entities = list;
    res.variableDisplay.valid = true;
    res.variableDisplay.nColumns = 3;
    res.variableDisplay.columnNames = ["I", "J", "VALUE"];
    res.variableDisplay.axisIndices = [0, 1, 2];
    res.variableDisplay.scale = 4.0f;
    return res;
}
