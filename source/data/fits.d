module fits;

import std.stdio;
import std.regex;
import std.string;
import std.conv;
import std.bitmanip;
import std.parallelism;
import std.algorithm;
import std.format;
import std.range;
import std.math;

// https://fits.gsfc.nasa.gov/fits_viewer.html#image_display

class FitsFile 
{
    fitsHeader header;
    fitsData data;
    string filePath;
    size_t dataOffsetBytes;
    
    private static ushort readBE16(const(ubyte)[] buf, size_t o)
    {
        return cast(ushort)((cast(uint)buf[o] << 8) | cast(uint)buf[o + 1]);
    }
    private static uint readBE32(const(ubyte)[] buf, size_t o)
    {
        return (cast(uint)buf[o] << 24) | (cast(uint)buf[o + 1] << 16) | (cast(uint)buf[o + 2] << 8) | cast(uint)buf[o + 3];
    }
    private static ulong readBE64(const(ubyte)[] buf, size_t o)
    {
        auto hi = readBE32(buf, o);
        auto lo = readBE32(buf, o + 4);
        return (cast(ulong)hi << 32) | cast(ulong)lo;
    }

    this(string _filePath) {
        this.filePath = _filePath;
        readHeader();
        printHeader();
        readData();
    }

    private static string trimCardValue(string v)
    {
        auto s = v.strip();
        if (s.length >= 2 && s[0] == '\'' && s[$-1] == '\'')
            return s[1 .. $-1];
        return s;
    }

    void readHeader() 
    {
        File fitsFile = File(filePath, "rb");

        bool foundEnd = false;
        size_t totalRead = 0;

        string SIMPLE = "";
        string SIMPLE_comments = "";
        int BITPIX = 0; string BITPIX_comments = "";
        int NAXIS = 0; string NAXIS_comments = "";
        int NAXIS1 = 1; string NAXIS1_comments = "";
        int NAXIS2 = 1; string NAXIS2_comments = "";
        int NAXIS3 = 1; string NAXIS3_comments = "";
        string EXTEND = "";
        double BSCALE = 1; string BSCALE_comments = "";
        double BZERO = 0; string BZERO_comments = "";

        while (!foundEnd)
        {
            ubyte[2_880] block;
            auto readBytes = fitsFile.rawRead(block[]);
            size_t n = readBytes.length;
            if (n != block.length)
            {
                throw new Exception("Unexpected EOF while reading FITS header");
            }
            totalRead += n;

            foreach (i; 0 .. block.length / 80)
            {
                auto cardBytes = block[i*80 .. (i+1)*80];
                auto card = cast(string) cardBytes.idup;
                auto keyword = card[0 .. 8].strip();
                if (keyword == "END")
                {
                    foundEnd = true;
                    break;
                }
                // FITS value cards: KEYWORD = VALUE / COMMENT
                if (card.length < 10)
                    continue;
                immutable hasEquals = card[8 .. 30].canFind('=');
                if (!hasEquals)
                    continue;
                size_t eqPos = card.indexOf('=');
                if (eqPos == size_t.max) continue;
                auto rest = card[eqPos + 1 .. $];
                string valuePart;
                string commentPart = "";
                auto slashPos = rest.indexOf('/');
                if (slashPos != -1)
                {
                    valuePart = rest[0 .. slashPos];
                    commentPart = rest[slashPos + 1 .. $];
                }
                else
                {
                    valuePart = rest;
                }
                valuePart = valuePart.strip();
                commentPart = commentPart.strip();

                switch (keyword)
                {
                    case "SIMPLE":
                        SIMPLE = trimCardValue(valuePart);
                        SIMPLE_comments = commentPart;
                        break;
                    case "BITPIX":
                        BITPIX = to!int(valuePart);
                        BITPIX_comments = commentPart;
                        break;
                    case "NAXIS":
                        NAXIS = to!int(valuePart);
                        NAXIS_comments = commentPart;
                        break;
                    case "NAXIS1":
                        NAXIS1 = to!int(valuePart);
                        NAXIS1_comments = commentPart;
                        break;
                    case "NAXIS2":
                        NAXIS2 = to!int(valuePart);
                        NAXIS2_comments = commentPart;
                        break;
                    case "NAXIS3":
                        NAXIS3 = to!int(valuePart);
                        NAXIS3_comments = commentPart;
                        break;
                    case "EXTEND":
                        EXTEND = trimCardValue(valuePart);
                        break;
                    case "BSCALE":
                        BSCALE = to!double(valuePart);
                        BSCALE_comments = commentPart;
                        break;
                    case "BZERO":
                        BZERO = to!double(valuePart);
                        BZERO_comments = commentPart;
                        break;
                    default:
                        break;
                }
            }
        }

        // Data offset is next 2880 boundary
        dataOffsetBytes = totalRead;

        this.header = fitsHeader(SIMPLE, SIMPLE_comments,
            BITPIX, BITPIX_comments, 
            NAXIS, NAXIS_comments,
            NAXIS1, NAXIS1_comments,
            NAXIS2, NAXIS2_comments,
            NAXIS3, NAXIS3_comments,
            EXTEND, 
            BSCALE, BSCALE_comments,
            BZERO, BZERO_comments
        );
    } 

    void readData()
    {
        if (header.NAXIS == 0)
        {
            this.data = fitsData.init;
            return;
        }
        File dataFile = File(filePath, "rb");
        dataFile.seek(cast(long)dataOffsetBytes);

        size_t nx = cast(size_t) header.NAXIS1;
        size_t ny = cast(size_t) (header.NAXIS >= 2 ? header.NAXIS2 : 1);
        size_t nz = cast(size_t) (header.NAXIS >= 3 ? header.NAXIS3 : 1);
        size_t count = nx * ny * nz;

        size_t elemSize = 0;
        if (header.BITPIX == 8)        elemSize = 1;   // unsigned byte
        else if (header.BITPIX == 16)  elemSize = 2;   // 16-bit signed
        else if (header.BITPIX == 32)  elemSize = 4;   // 32-bit signed
        else if (header.BITPIX == 64)  elemSize = 8;   // 64-bit signed
        else if (header.BITPIX == -32) elemSize = 4;   // 32-bit float
        else if (header.BITPIX == -64) elemSize = 8;   // 64-bit float
        else
            throw new Exception("Unsupported BITPIX: " ~ to!string(header.BITPIX));

        auto raw = new ubyte[](count * elemSize);
        auto readData = dataFile.rawRead(raw);
        size_t n = readData.length;
        if (n != raw.length)
        {
            throw new Exception("Unexpected EOF while reading FITS data");
        }

        float[] values;
        values.length = count;
        // Convert big-endian to native and scale
        if (header.BITPIX == 8)
        {
            foreach (i; 0 .. count)
            {
                auto v = cast(ubyte) raw[i];
                values[i] = cast(float)(header.BSCALE * v + header.BZERO);
            }
        }
        else if (header.BITPIX == 16)
        {
            foreach (i; 0 .. count)
            {
                size_t o = i * 2;
                ushort be = (cast(ushort)raw[o] << 8) | cast(ushort)raw[o + 1];
                short v = cast(short) be;
                values[i] = cast(float)(header.BSCALE * v + header.BZERO);
            }
        }
        else if (header.BITPIX == 32)
        {
            foreach (i; 0 .. count)
            {
                size_t o = i * 4;
                uint be = (cast(uint)raw[o] << 24) | (cast(uint)raw[o + 1] << 16) | (cast(uint)raw[o + 2] << 8) | (cast(uint)raw[o + 3]);
                int v = cast(int) be;
                values[i] = cast(float)(header.BSCALE * v + header.BZERO);
            }
        }
        else if (header.BITPIX == 64)
        {
            foreach (i; 0 .. count)
            {
                size_t o = i * 8;
                ulong be = (cast(ulong)raw[o] << 56) | (cast(ulong)raw[o + 1] << 48) | (cast(ulong)raw[o + 2] << 40) | (cast(ulong)raw[o + 3] << 32) |
                           (cast(ulong)raw[o + 4] << 24) | (cast(ulong)raw[o + 5] << 16) | (cast(ulong)raw[o + 6] << 8) | (cast(ulong)raw[o + 7]);
                long v = cast(long) be;
                // May overflow float range; cast via double
                values[i] = cast(float)(header.BSCALE * cast(double)v + header.BZERO);
            }
        }
        else if (header.BITPIX == -32)
        {
            foreach (i; 0 .. count)
            {
                size_t o = i * 4;
                uint bitsLE = (cast(uint)raw[o]) |
                              (cast(uint)raw[o + 1] << 8) |
                              (cast(uint)raw[o + 2] << 16) |
                              (cast(uint)raw[o + 3] << 24);
                float fv = *cast(float*) &bitsLE; // reinterpret bits
                values[i] = cast(float)(header.BSCALE * fv + header.BZERO);
            }
        }
        else if (header.BITPIX == -64)
        {
            foreach (i; 0 .. count)
            {
                size_t o = i * 8;
                ulong bitsLE = (cast(ulong)raw[o]) |
                               (cast(ulong)raw[o + 1] << 8) |
                               (cast(ulong)raw[o + 2] << 16) |
                               (cast(ulong)raw[o + 3] << 24) |
                               (cast(ulong)raw[o + 4] << 32) |
                               (cast(ulong)raw[o + 5] << 40) |
                               (cast(ulong)raw[o + 6] << 48) |
                               (cast(ulong)raw[o + 7] << 56);
                double dv = *cast(double*) &bitsLE;
                values[i] = cast(float)(header.BSCALE * dv + header.BZERO);
            }
        }
        else
        {
            assert(0);
        }

        this.data = fitsData(values, header.NAXIS, nx, ny, nz);
    }

    void printHeader()
    {
        writeln("SIMPLE: ", header.SIMPLE);
        write("BITPIX: ", header.BITPIX); writeln("\tComments: ", header._BITPIX_comments);
        write("NAXIS: " , header.NAXIS); writeln("\tComments: ", header._NAXIS_comments);
        write("NAXIS1: ", header.NAXIS1); writeln("\tComments: ", header._NAXIS1_comments);
        writeln("NAXIS2: ", header.NAXIS2);
        writeln("NAXIS3: ", header.NAXIS3);
        writeln("EXTEND: ", header.EXTEND);
        writeln("BSCALE: ", header.BSCALE);
        writeln("BZERO: " , header.BZERO);
    }
}

struct fitsHeader {
    string SIMPLE; string _SIMPLE_comments;
    int BITPIX; string _BITPIX_comments;
    int NAXIS ; string _NAXIS_comments;
    int NAXIS1 ; string _NAXIS1_comments;
    int NAXIS2 ; string _NAXIS2_comments;
    int NAXIS3 ; string _NAXIS3_comments;
    string EXTEND;
    double BSCALE ; string _BSCALE_comments;
    double BZERO ; string _BZERO_comments;
} 

struct fitsData {
    float[] values;
    size_t naxis;
    size_t nx;
    size_t ny;
    size_t nz;
    this(float[] v, size_t n, size_t _nx, size_t _ny, size_t _nz)
    {
        values = v;
        naxis = n;
        nx = _nx;
        ny = _ny;
        nz = _nz;
    }
}

/***
// https://fits.gsfc.nasa.gov/fits_primer.html
    SIMPLE  =  T / conforms to FITS standard
    BITPIX  =                   16 / array data type
    NAXIS   =                    3 / number of array dimensions
    NAXIS1  =                 1000
    NAXIS2  =                  173
    NAXIS3  =                 1000
    EXTEND  =                    T
    BSCALE  =                    1
    BZERO   =                32768
    END
*/

