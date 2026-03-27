/**
 * Quoted-field CSV/TSV reader for generic tabular ingest.
 */
module csv_reader;

import std.file;
import std.string;
import std.conv;
import std.algorithm;
import std.array;

class CSVReader
{
    private string filePath;
    private string[] headers;
    private string[][] rows;
    private char delimiter;

    this(string _filePath)
    {
        this.filePath = _filePath;
        this.delimiter = ',';
        read();
    }

    this(string _filePath, char _delimiter)
    {
        this.filePath = _filePath;
        this.delimiter = _delimiter;
        read();
    }

    private void read()
    {
        // Use readText + splitLines instead of std.stdio.File.byLine/readln: on Android, Phobos
        // line I/O can leave readlnImpl unresolved (_IO_FILE vs __sFILE mangling vs Bionic).
        string content = readText(filePath);
        string[] lines = splitLines(content);
        if (lines.length == 0)
        {
            headers = [];
            rows = [];
            return;
        }
        headers = parseLine(lines[0], delimiter);
        rows = [];
        foreach (line; lines[1 .. $])
        {
            string[] row = parseLine(line, delimiter);
            if (row.length > 0)
                rows ~= row;
        }
    }

    private string[] parseLine(string line, char delim)
    {
        string[] result;
        bool inQuotes = false;
        string currentField = "";

        foreach (char c; line)
        {
            if (c == '"')
                inQuotes = !inQuotes;
            else if (c == delim && !inQuotes)
            {
                result ~= currentField.strip();
                currentField = "";
            }
            else
                currentField ~= c;
        }
        result ~= currentField.strip();
        return result;
    }

    static char detectDelimiter(string filePath)
    {
        string content = readText(filePath);
        string[] lines = splitLines(content);
        if (lines.length == 0)
            return ',';
        return lines[0].indexOf('\t') >= 0 ? '\t' : ',';
    }

    string[] getHeaders() { return headers; }

    string[][] getRows() { return rows; }

    size_t getRowCount() { return rows.length; }

    int getColumnIndex(string columnName)
    {
        foreach (i, header; headers)
        {
            if (header.toLower() == columnName.toLower())
                return cast(int) i;
        }
        return -1;
    }

    string getValue(string[] row, string columnName)
    {
        int idx = getColumnIndex(columnName);
        if (idx >= 0 && idx < row.length)
            return row[idx];
        return "";
    }
}
