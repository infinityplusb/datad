module model.base_data;

import std.conv;
import std.file : readText;
import std.string : splitLines;
import std.array : split;
import std.algorithm : min;

/** A single data column in a columnar table. */
struct DataColumn(T)
{
    string name;
    T[] values;
}

/**
 * Type-agnostic tabular data object.
 *
 * Data is stored in columnar format (`dataTable`) so consumers can pull one
 * column at a time efficiently (useful for plotting pipelines).
 */
class DataObject(T = string)
{
    DataColumn!T[] dataTable;
    string sourcePath;

    this(string fileLocation)
    {
        sourcePath = fileLocation;
        load(fileLocation);
    }

    final void load(string fileLocation)
    {
        dataTable = [];
        string[] lines = splitLines(readText(fileLocation));
        if (lines.length == 0)
            return;

        string[] headers = lines[0].split(",");
        foreach (header; headers)
        {
            DataColumn!T col;
            col.name = header;
            dataTable ~= col;
        }

        foreach (ln; lines[1 .. $])
        {
            string[] record = ln.split(",");
            size_t count = min(record.length, dataTable.length);
            foreach (idx; 0 .. count)
                dataTable[idx].values ~= to!T(record[idx]);
        }
    }

    size_t rowCount() const
    {
        return dataTable.length > 0 ? dataTable[0].values.length : 0;
    }
}

/** Backward-compatible CSV table type. */
alias CsvTable = DataObject!string;
