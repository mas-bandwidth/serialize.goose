/* fuzz/host.c -- the serialize.c v1.11.2 side of the differential.
 *
 * The Goose test generates one program, encodes it in the fixed 96-byte
 * record stream described in fuzz/differential_test.goose, and calls these
 * two functions.  Both codecs therefore run in one process over the same
 * program and the same bytes (JOB.md, THE TASK).  serialize.c is header-only
 * at the pin; serialize.c itself is compiled as an empty translation unit so
 * the sidecar names exactly the pin's files (DESIGN.md, "The reference").
 *
 * c_write returns the meaningful byte count or -1 on a bad call.
 * c_read returns the number of operations accepted; the decoded values are
 * written to out as records of the same shape, one per accepted operation.
 */

#include <stdint.h>
#include <string.h>
#include <wchar.h>

#include "serialize.h"

#define REC 96
#define REC_DATA 56
#define REC_DATA_LEN 40

enum
{
    OP_BITS = 0, OP_BITS64, OP_BOOL, OP_UINT8, OP_UINT16, OP_UINT32,
    OP_UINT64, OP_UINT128, OP_INT, OP_INT64, OP_INT128, OP_INT_RELATIVE,
    OP_FIXED32, OP_FIXED64, OP_FIXED128, OP_FLOAT, OP_DOUBLE,
    OP_COMPRESSED, OP_BYTES, OP_STRING, OP_WSTRING, OP_ALIGN, OP_OBJECT
};

static int negative_control = 0;

/* The test-only switch: with it set, every ranged int is written one bit
 * wider than the program declares, so the byte comparison must go red. */
void c_negative_control( void )
{
    negative_control = 1;
}

static uint32_t rd32( const uint8_t * p )
{
    return (uint32_t) p[0] | ( (uint32_t) p[1] << 8 ) | ( (uint32_t) p[2] << 16 ) | ( (uint32_t) p[3] << 24 );
}

static uint64_t rd64( const uint8_t * p )
{
    return (uint64_t) rd32( p ) | ( (uint64_t) rd32( p + 4 ) << 32 );
}

static void wr32( uint8_t * p, uint32_t v )
{
    p[0] = (uint8_t) v; p[1] = (uint8_t) ( v >> 8 ); p[2] = (uint8_t) ( v >> 16 ); p[3] = (uint8_t) ( v >> 24 );
}

static void wr64( uint8_t * p, uint64_t v )
{
    wr32( p, (uint32_t) v ); wr32( p + 4, (uint32_t) ( v >> 32 ) );
}

static float f32_of( uint64_t bits )
{
    float f;
    uint32_t b = (uint32_t) bits;
    memcpy( &f, &b, 4 );
    return f;
}

static uint32_t f32_bits( float f )
{
    uint32_t b;
    memcpy( &b, &f, 4 );
    return b;
}

static double f64_of( uint64_t bits )
{
    double d;
    memcpy( &d, &bits, 8 );
    return d;
}

static uint64_t f64_bits( double d )
{
    uint64_t b;
    memcpy( &b, &d, 8 );
    return b;
}

int64_t c_write( const uint8_t * prog, int64_t prog_len, uint8_t * out, int64_t out_cap )
{
    serialize_write_stream_t s;
    int64_t n, i;

    if ( prog_len % REC != 0 || out_cap % 8 != 0 ) return -1;
    serialize_write_stream_init( &s, out, (int) out_cap );
    n = prog_len / REC;
    for ( i = 0; i < n; i++ )
    {
        const uint8_t * r = prog + i * REC;
        uint32_t kind = rd32( r );
        uint64_t a = rd64( r + 8 ), b = rd64( r + 16 ), c = rd64( r + 24 );
        uint64_t d = rd64( r + 32 ), e = rd64( r + 40 ), f = rd64( r + 48 );
        uint32_t len = rd32( r + 4 );
        switch ( kind )
        {
            case OP_BITS: serialize_write_bits( &s, (uint32_t) a, (int) b ); break;
            case OP_BITS64: serialize_write_bits64( &s, a, (int) b ); break;
            case OP_BOOL: serialize_write_bool( &s, (int) a ); break;
            case OP_UINT8: serialize_write_uint8( &s, (uint8_t) a ); break;
            case OP_UINT16: serialize_write_uint16( &s, (uint16_t) a ); break;
            case OP_UINT32: serialize_write_uint32( &s, (uint32_t) a ); break;
            case OP_UINT64: serialize_write_uint64( &s, a ); break;
            case OP_UINT128: serialize_write_uint128( &s, serialize_uint128_make( b, a ) ); break;
            case OP_INT:
            {
                int32_t mn = (int32_t) (uint32_t) b, mx = (int32_t) (uint32_t) c;
                if ( negative_control && mn <= mx )
                {
                    int bits = serialize_bits_required( (uint32_t) mn, (uint32_t) mx );
                    if ( bits > 0 && bits < 32 ) mn -= (int32_t) ( (uint32_t) 1 << bits );
                }
                serialize_write_int( &s, (int32_t) (uint32_t) a, mn, mx );
                break;
            }
            case OP_INT64: serialize_write_int64( &s, (int64_t) a, (int64_t) b, (int64_t) c ); break;
            case OP_INT128: serialize_write_int128( &s, serialize_int128_make( b, a ), serialize_int128_make( d, c ), serialize_int128_make( f, e ) ); break;
            case OP_INT_RELATIVE: serialize_write_int_relative( &s, (int32_t) (uint32_t) a, (int32_t) (uint32_t) b ); break;
            case OP_FIXED32: serialize_write_fixed32( &s, (int32_t) (uint32_t) a, (int) b, (int) c, (int32_t) (uint32_t) d, (int32_t) (uint32_t) e ); break;
            case OP_FIXED64: serialize_write_fixed64( &s, (int64_t) a, (int) b, (int) c, (int64_t) d, (int64_t) e ); break;
            case OP_FIXED128: serialize_write_fixed128( &s, serialize_int128_make( b, a ), (int) c, (int) d, (int64_t) e, (int64_t) f ); break;
            case OP_FLOAT: serialize_write_float( &s, f32_of( a ) ); break;
            case OP_DOUBLE: serialize_write_double( &s, f64_of( a ) ); break;
            case OP_COMPRESSED: serialize_write_compressed_float( &s, f32_of( a ), f32_of( b ), f32_of( c ), f32_of( d ) ); break;
            case OP_BYTES: serialize_write_bytes( &s, r + REC_DATA, (int) len ); break;
            case OP_STRING:
            {
                char tmp[REC_DATA_LEN + 1];
                memcpy( tmp, r + REC_DATA, len );
                tmp[len] = 0;
                serialize_write_string( &s, tmp, (int) d );
                break;
            }
            case OP_WSTRING:
            {
                wchar_t tmp[REC_DATA_LEN + 1];
                uint32_t j;
                for ( j = 0; j < len; j++ ) tmp[j] = (wchar_t) r[REC_DATA + j];
                tmp[len] = 0;
                serialize_write_wstring( &s, tmp, (int) d );
                break;
            }
            case OP_ALIGN: serialize_write_align( &s ); break;
            case OP_OBJECT: serialize_write_int( &s, (int32_t) (uint32_t) a, (int32_t) (uint32_t) b, (int32_t) (uint32_t) c ); break;
            default: return -1;
        }
    }
    serialize_write_flush( &s );
    return serialize_write_bytes_processed( &s );
}

static void rec_init( uint8_t * r, uint32_t kind )
{
    memset( r, 0, REC );
    wr32( r, kind );
}

int64_t c_read( uint8_t * out, int64_t out_cap, const uint8_t * prog, int64_t prog_len, const uint8_t * data, int64_t data_len, int64_t bytes )
{
    serialize_read_stream_t s;
    int64_t n, i, steps = 0;

    if ( prog_len % REC != 0 || out_cap < ( prog_len / REC ) * REC ) return -1;
    if ( bytes < 0 || data_len < bytes + 8 ) return -1;
    serialize_read_stream_init( &s, data, (int) bytes );
    n = prog_len / REC;
    for ( i = 0; i < n; i++ )
    {
        const uint8_t * r = prog + i * REC;
        uint8_t * o = out + i * REC;
        uint32_t kind = rd32( r );
        uint64_t b = rd64( r + 16 ), c = rd64( r + 24 );
        uint64_t d = rd64( r + 32 ), e = rd64( r + 40 ), f = rd64( r + 48 );
        uint32_t len = rd32( r + 4 );
        int ok = 0;
        rec_init( o, kind );
        switch ( kind )
        {
            case OP_BITS:
            {
                uint32_t v = 0; ok = serialize_read_bits( &s, &v, (int) b ); if ( ok ) wr64( o + 8, v ); break;
            }
            case OP_BITS64:
            {
                uint64_t v = 0; ok = serialize_read_bits64( &s, &v, (int) b ); if ( ok ) wr64( o + 8, v ); break;
            }
            case OP_BOOL:
            {
                int v = 0; ok = serialize_read_bool( &s, &v ); if ( ok ) wr64( o + 8, (uint64_t) ( v != 0 ) ); break;
            }
            case OP_UINT8:
            {
                uint8_t v = 0; ok = serialize_read_uint8( &s, &v ); if ( ok ) wr64( o + 8, v ); break;
            }
            case OP_UINT16:
            {
                uint16_t v = 0; ok = serialize_read_uint16( &s, &v ); if ( ok ) wr64( o + 8, v ); break;
            }
            case OP_UINT32:
            {
                uint32_t v = 0; ok = serialize_read_uint32( &s, &v ); if ( ok ) wr64( o + 8, v ); break;
            }
            case OP_UINT64:
            {
                uint64_t v = 0; ok = serialize_read_uint64( &s, &v ); if ( ok ) wr64( o + 8, v ); break;
            }
            case OP_UINT128:
            {
                serialize_uint128_t v = serialize_uint128_make( 0, 0 );
                ok = serialize_read_uint128( &s, &v );
                if ( ok ) { wr64( o + 8, v.lo ); wr64( o + 16, v.hi ); }
                break;
            }
            case OP_INT:
            {
                int32_t v = 0;
                ok = serialize_read_int( &s, &v, (int32_t) (uint32_t) b, (int32_t) (uint32_t) c );
                if ( ok ) wr64( o + 8, (uint64_t) (int64_t) v );
                break;
            }
            case OP_INT64:
            {
                int64_t v = 0; ok = serialize_read_int64( &s, &v, (int64_t) b, (int64_t) c ); if ( ok ) wr64( o + 8, (uint64_t) v ); break;
            }
            case OP_INT128:
            {
                serialize_int128_t v = serialize_int128_make( 0, 0 );
                ok = serialize_read_int128( &s, &v, serialize_int128_make( d, c ), serialize_int128_make( f, e ) );
                if ( ok ) { wr64( o + 8, v.lo ); wr64( o + 16, v.hi ); }
                break;
            }
            case OP_INT_RELATIVE:
            {
                int32_t v = 0;
                ok = serialize_read_int_relative( &s, (int32_t) (uint32_t) rd64( r + 8 ), &v );
                if ( ok ) wr64( o + 8, (uint64_t) (int64_t) v );
                break;
            }
            case OP_FIXED32:
            {
                int32_t v = 0;
                ok = serialize_read_fixed32( &s, &v, (int) b, (int) c, (int32_t) (uint32_t) d, (int32_t) (uint32_t) e );
                if ( ok ) wr64( o + 8, (uint64_t) (int64_t) v );
                break;
            }
            case OP_FIXED64:
            {
                int64_t v = 0; ok = serialize_read_fixed64( &s, &v, (int) b, (int) c, (int64_t) d, (int64_t) e ); if ( ok ) wr64( o + 8, (uint64_t) v ); break;
            }
            case OP_FIXED128:
            {
                serialize_int128_t v = serialize_int128_make( 0, 0 );
                ok = serialize_read_fixed128( &s, &v, (int) c, (int) d, (int64_t) e, (int64_t) f );
                if ( ok ) { wr64( o + 8, v.lo ); wr64( o + 16, v.hi ); }
                break;
            }
            case OP_FLOAT:
            {
                float v = 0; ok = serialize_read_float( &s, &v ); if ( ok ) wr64( o + 8, f32_bits( v ) ); break;
            }
            case OP_DOUBLE:
            {
                double v = 0; ok = serialize_read_double( &s, &v ); if ( ok ) wr64( o + 8, f64_bits( v ) ); break;
            }
            case OP_COMPRESSED:
            {
                float v = 0;
                ok = serialize_read_compressed_float( &s, &v, f32_of( b ), f32_of( c ), f32_of( d ) );
                if ( ok ) wr64( o + 8, f32_bits( v ) );
                break;
            }
            case OP_BYTES:
            {
                ok = serialize_read_bytes( &s, o + REC_DATA, (int) len );
                if ( ok ) wr32( o + 4, len );
                break;
            }
            case OP_STRING:
            {
                char tmp[REC_DATA_LEN + 1];
                memset( tmp, 0, sizeof( tmp ) );
                ok = serialize_read_string( &s, tmp, (int) d );
                if ( ok )
                {
                    uint32_t j, m = (uint32_t) strlen( tmp );
                    wr32( o + 4, m );
                    for ( j = 0; j < m && j < REC_DATA_LEN; j++ ) o[REC_DATA + j] = (uint8_t) tmp[j];
                }
                break;
            }
            case OP_WSTRING:
            {
                wchar_t tmp[REC_DATA_LEN + 1];
                memset( tmp, 0, sizeof( tmp ) );
                ok = serialize_read_wstring( &s, tmp, (int) d );
                if ( ok )
                {
                    uint32_t j = 0, m = 0;
                    while ( tmp[m] != 0 )
                    {
                        uint32_t cp = (uint32_t) tmp[m++];
                        if ( cp < 0x80 ) { o[REC_DATA + j++] = (uint8_t) cp; }
                        else if ( cp < 0x800 )
                        {
                            o[REC_DATA + j++] = (uint8_t) ( 0xC0 | ( cp >> 6 ) );
                            o[REC_DATA + j++] = (uint8_t) ( 0x80 | ( cp & 0x3F ) );
                        }
                        else if ( cp < 0x10000 )
                        {
                            o[REC_DATA + j++] = (uint8_t) ( 0xE0 | ( cp >> 12 ) );
                            o[REC_DATA + j++] = (uint8_t) ( 0x80 | ( ( cp >> 6 ) & 0x3F ) );
                            o[REC_DATA + j++] = (uint8_t) ( 0x80 | ( cp & 0x3F ) );
                        }
                        else
                        {
                            o[REC_DATA + j++] = (uint8_t) ( 0xF0 | ( cp >> 18 ) );
                            o[REC_DATA + j++] = (uint8_t) ( 0x80 | ( ( cp >> 12 ) & 0x3F ) );
                            o[REC_DATA + j++] = (uint8_t) ( 0x80 | ( ( cp >> 6 ) & 0x3F ) );
                            o[REC_DATA + j++] = (uint8_t) ( 0x80 | ( cp & 0x3F ) );
                        }
                        if ( j > REC_DATA_LEN - 4 ) break;
                    }
                    wr32( o + 4, j );
                }
                break;
            }
            case OP_ALIGN: ok = serialize_read_align( &s ); break;
            case OP_OBJECT:
            {
                int32_t v = 0;
                ok = serialize_read_int( &s, &v, (int32_t) (uint32_t) b, (int32_t) (uint32_t) c );
                if ( ok ) wr64( o + 8, (uint64_t) (int64_t) v );
                break;
            }
            default: return -1;
        }
        if ( !ok ) break;
        steps++;
    }
    return steps;
}
