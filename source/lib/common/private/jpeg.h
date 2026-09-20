/*! @file jpeg.h
 *
 *  @brief JPEG (JPG) encoding helpers for the GPR SDK.
 *
 *  Encodes interleaved 8-bit RGB into an in-memory JPEG, embedding an EXIF
 *  Orientation tag so that viewers display the image the right way up without
 *  the pixels being physically rotated. Wraps the tiny_jpeg encoder.
 *
 *  (C) Copyright 2018 GoPro Inc (http://gopro.com/).
 *
 *  Licensed under either:
 *  - Apache License, Version 2.0, http://www.apache.org/licenses/LICENSE-2.0
 *  - MIT license, http://opensource.org/licenses/MIT
 *  at your option.
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

#ifndef GPR_JPEG_H
#define GPR_JPEG_H

#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#include "gpr_buffer.h"

#ifdef __cplusplus
extern "C" {
#endif

// Read the pixel dimensions of a JPEG image from its header, without decoding it.
// Walks the marker segments until the Start-Of-Frame (SOF) marker, which carries the
// height and width. Returns 1 and fills *width/*height on success, 0 otherwise.
static int gpr_jpeg_get_dimensions( const unsigned char* d, size_t n, int* width, int* height )
{
    size_t i;

    if( d == NULL || n < 4 || d[0] != 0xFF || d[1] != 0xD8 ) // SOI
        return 0;

    i = 2;
    while( i + 1 < n )
    {
        unsigned char marker;
        int seg_len;
        bool is_sof;

        if( d[i] != 0xFF ) { i++; continue; }    // skip fill bytes until a marker
        marker = d[i + 1];
        i += 2;

        // Standalone markers carry no length: SOI, EOI, TEM and the restart markers.
        if( marker == 0xD8 || marker == 0xD9 || marker == 0x01 || ( marker >= 0xD0 && marker <= 0xD7 ) )
            continue;

        if( i + 2 > n )
            break;

        seg_len = ( d[i] << 8 ) | d[i + 1];      // length includes these 2 bytes
        if( seg_len < 2 )
            break;

        // SOF markers (0xC0-0xCF) carry the frame dimensions, except DHT(C4), JPG(C8), DAC(CC).
        is_sof = ( marker >= 0xC0 && marker <= 0xCF ) && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
        if( is_sof )
        {
            if( i + 7 > n )                      // length(2) precision(1) height(2) width(2)
                break;

            *height = ( d[i + 3] << 8 ) | d[i + 4];
            *width  = ( d[i + 5] << 8 ) | d[i + 6];
            return ( *width > 0 && *height > 0 ) ? 1 : 0;
        }

        i += seg_len;                            // skip this segment
    }

    return 0;
}

// The remaining helpers encode JPEGs and depend on the tiny_jpeg encoder, so they are only
// available when JPEG writing is compiled in (GPR_JPEG_AVAILABLE).
#if GPR_JPEG_AVAILABLE

#include "tiny_jpeg.h"

// Growable byte buffer used to collect the JPEG produced by tje_encode_with_func.
// tiny_jpeg gives its sink no way to report failure or negotiate space, and JPEG output has no
// useful upper bound (high-entropy content measures ~3 bytes/pixel at quality 2 where typical
// content measures ~1.25), so the sink grows on demand instead of assuming a compression ratio.
// An allocation failure while growing sets `failed` and stops collecting; the bytes gathered so
// far are truncated, so the caller must treat the whole encode as failed. sink.data is owned by
// the sink and remains valid (for the caller to free) even after a failure.
typedef struct
{
    unsigned char*  data;
    size_t          size;
    size_t          capacity;
    bool            failed;

} gpr_jpg_sink;

static void gpr_jpg_sink_write( void* context, void* data, int size )
{
    gpr_jpg_sink* sink = (gpr_jpg_sink*)context;

    if( sink->failed )
        return;

    if( sink->size + (size_t)size > sink->capacity )
    {
        size_t new_capacity = sink->capacity ? sink->capacity : ( 1 << 20 );
        while( new_capacity < sink->size + (size_t)size )
            new_capacity *= 2;

        unsigned char* grown = (unsigned char*)realloc( sink->data, new_capacity );
        if( grown == NULL )
        {
            sink->failed = true;
            return;
        }

        sink->data     = grown;
        sink->capacity = new_capacity;
    }

    memcpy( sink->data + sink->size, data, (size_t)size );
    sink->size += (size_t)size;
}

#endif // GPR_JPEG_AVAILABLE

#ifdef __cplusplus
}
#endif

#endif // GPR_JPEG_H
