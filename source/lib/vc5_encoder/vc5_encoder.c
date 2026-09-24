/*! @file vc5_encoder.c
 *
 *  @brief Implementation of the top level vc5 encoder data structures and functions.
 *
 *  @version 1.0.0
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

#include "headers.h"

void vc5_encoder_parameters_set_default(vc5_encoder_parameters* encoding_parameters)
{
    encoding_parameters->enabled_parts      = VC5_ENABLED_PARTS;
    encoding_parameters->input_width        = 4000;
    encoding_parameters->input_height       = 3000;
    encoding_parameters->input_pitch        = 4000;
    
    encoding_parameters->pixel_format       = VC5_ENCODER_PIXEL_FORMAT_DEFAULT;
    encoding_parameters->quality_setting    = VC5_ENCODER_QUALITY_SETTING_DEFAULT;

    encoding_parameters->mem_alloc = malloc;
    encoding_parameters->mem_free  = free;

    rgb_parameters_set_default(&encoding_parameters->rgb_params);
}

/*!
 @brief Free the output of a failed encode and leave the caller an empty buffer

 The caller cannot tell a partial bitstream from a complete one, so a failed encode
 hands back neither the bitstream nor the thumbnail rendered alongside it.
 */
static void ReleaseEncoderOutput(const vc5_encoder_parameters* encoding_parameters, gpr_buffer* vc5_buffer, RGB_IMAGE* rgb_image)
{
    if (vc5_buffer->buffer != NULL) {
        encoding_parameters->mem_free(vc5_buffer->buffer);
    }
    vc5_buffer->buffer = NULL;
    vc5_buffer->size = 0;

    if (rgb_image->buffer != NULL) {
        encoding_parameters->mem_free(rgb_image->buffer);
        rgb_image->buffer = NULL;
    }
}

/*!
 @brief Encode a raw frame into a VC-5 bitstream

 On success vc5_buffer holds the bitstream, allocated with mem_alloc and owned by the
 caller. On any error vc5_buffer is left empty (NULL, 0), rgb_buffer is not written,
 and nothing the call allocated is left behind.
 */
CODEC_ERROR vc5_encoder_process(const vc5_encoder_parameters*   encoding_parameters,    /* vc5 encoding parameters */
                                const gpr_buffer*               raw_buffer,             /* raw input buffer. */
                                      gpr_buffer*               vc5_buffer,
                                      gpr_rgb_buffer*           rgb_buffer)             /* rgb output buffer. */
{
    CODEC_ERROR error = CODEC_ERROR_OKAY;
    IMAGE image;
    ENCODER_PARAMETERS parameters;
    
    STREAM bitstream_file;
    
    // Nothing is handed back until the encode succeeds
    vc5_buffer->buffer = NULL;
    vc5_buffer->size = 0;

    // Refuse a frame the wavelet filters would run outside of (see VC5_ENCODER_MIN_FRAME_SIZE):
    // they read before and past a level's input (4 bytes before it when its rows are 4 samples
    // wide), and a level 2 rows tall or fewer (a frame under 18 rows) wraps the transform's last
    // middle row index round, so it writes past the wavelet
    if (encoding_parameters->input_width < VC5_ENCODER_MIN_FRAME_SIZE ||
        encoding_parameters->input_height < VC5_ENCODER_MIN_FRAME_SIZE) {
        return CODEC_ERROR_IMAGE_DIMENSIONS;
    }

    // Size the output for the worst case rather than for a compression ratio: 12-bit noise
    // encodes to 8.4 bits per pixel at Filmscan-X and 11.1 at Ultra, past the 8 (16-bit input)
    // or 6 (packed input) that half of the input buffer allowed. Each of the four channels is a
    // quarter of the frame, and its three wavelet levels code one coefficient per pixel plus the
    // padding that rounds each level up to an even size, at most 7 rows and 7 columns in all.
    // No coefficient takes more than MAX_CODED_COEFFICIENT_BITS. Everything else is at most
    // 1976 bytes, within the 4 KB allowed for it: 72 of image header and identifier, and per
    // channel 102 tag segments, nine 26-bit band end codewords and ten paddings of up to 31
    // bits, 476 bytes (1598 to 1624 bytes measured). The bit count passes 32 bits at about 159
    // megapixels, so the size is computed in 64 bits and refused if it does not fit a size_t.
    const uint64_t max_channel_coefficients = ((uint64_t)encoding_parameters->input_width / 2 + 7) *
                                              ((uint64_t)encoding_parameters->input_height / 2 + 7);
    const uint64_t max_vc5_buffer_bytes = (4 * max_channel_coefficients * MAX_CODED_COEFFICIENT_BITS) / 8 + 4096;

    if (max_vc5_buffer_bytes > SIZE_MAX) {
        return CODEC_ERROR_OUTOFMEMORY;
    }

    const size_t max_vc5_buffer_size = (size_t)max_vc5_buffer_bytes;

    // Initialize the data structure for passing parameters to the encoder
    InitEncoderParameters(&parameters);
    
    {
        QUANT quant_table[VC5_ENCODER_QUALITY_SETTING_COUNT][sizeof(parameters.quant_table) / sizeof(parameters.quant_table[0])] = {
            {1, 24, 24, 12, 64, 64, 48, 512, 512, 768}, // CineForm Low
            {1, 24, 24, 12, 48, 48, 32, 256, 256, 384}, // CineForm Medium
            {1, 24, 24, 12, 32, 32, 24, 128, 128, 192}, // CineForm High
            {1, 24, 24, 12, 24, 24, 12, 96, 96, 144},   // CineForm Filmscan-1
            {1, 24, 24, 12, 24, 24, 12, 64, 64, 96},    // CineForm Filmscan-X
            {1, 24, 24, 12, 24, 24, 12, 32, 32, 48},    // CineForm Filmscan-2
            {1, 24, 24, 12, 24, 24, 12, 24, 24, 32}     // CineForm Ultra
        };
        
        if( encoding_parameters->quality_setting < VC5_ENCODER_QUALITY_SETTING_COUNT )
        {
            memcpy(parameters.quant_table, quant_table[encoding_parameters->quality_setting], sizeof(parameters.quant_table));
        }
    }
    
    parameters.enabled_parts  = encoding_parameters->enabled_parts;
    parameters.encoded.format = IMAGE_FORMAT_RAW;

    // Resolution and rendering parameters of the RGB preview/thumbnail produced alongside
    // the encoded bitstream
    parameters.rgb_params = encoding_parameters->rgb_params;
    
#if VC5_ENABLED_PART(VC5_PART_LAYERS)
    // Test interlaced encoding using one layer per field
    parameters.layer_count = 2;
    parameters.progressive = 0;
    parameters.decompositor = DecomposeFields;
#endif
    
    parameters.allocator.Alloc = encoding_parameters->mem_alloc;
    parameters.allocator.Free = encoding_parameters->mem_free;
    
    // Check that the enabled parts are correct
    error = CheckEnabledParts(&parameters.enabled_parts);
    if (error != CODEC_ERROR_OKAY) {
        return error;
    }
    
    image.buffer = raw_buffer->buffer;
    
    image.width  = encoding_parameters->input_width;
    image.height = encoding_parameters->input_height;
    image.pitch  = encoding_parameters->input_pitch;
    image.size   = image.width * image.height * 2;
    image.offset = 0;

    switch( encoding_parameters->pixel_format )
    {
        case VC5_ENCODER_PIXEL_FORMAT_RGGB_12:
            image.format = PIXEL_FORMAT_RAW_RGGB_12;
            break;

        case VC5_ENCODER_PIXEL_FORMAT_RGGB_12P:
            image.format = PIXEL_FORMAT_RAW_RGGB_12P;
            break;
            
        case VC5_ENCODER_PIXEL_FORMAT_RGGB_14:
            image.format = PIXEL_FORMAT_RAW_RGGB_14;
            break;
            
        case VC5_ENCODER_PIXEL_FORMAT_GBRG_12:
            image.format = PIXEL_FORMAT_RAW_GBRG_12;
            break;
            
        case VC5_ENCODER_PIXEL_FORMAT_GBRG_12P:
            image.format = PIXEL_FORMAT_RAW_GBRG_12P;
            break;

        case VC5_ENCODER_PIXEL_FORMAT_BGGR_12:
            image.format = PIXEL_FORMAT_RAW_BGGR_12;
            break;

        case VC5_ENCODER_PIXEL_FORMAT_BGGR_14:
            image.format = PIXEL_FORMAT_RAW_BGGR_14;
            break;

        case VC5_ENCODER_PIXEL_FORMAT_RGGB_16:
            image.format = PIXEL_FORMAT_RAW_RGGB_16;
            break;

        case VC5_ENCODER_PIXEL_FORMAT_GBRG_16:
            image.format = PIXEL_FORMAT_RAW_GBRG_16;
            break;

        case VC5_ENCODER_PIXEL_FORMAT_BGGR_16:
            image.format = PIXEL_FORMAT_RAW_BGGR_16;
            break;

        default:
            assert(0);
    }
    
    // Set the dimensions and pixel format of the packed input image
    {
        parameters.input.width = image.width;
        parameters.input.height = image.height;
        parameters.input.format = image.format;
    }
    
#if VC5_ENABLED_PART(VC5_PART_LAYERS)
    // Test interlaced encoding using one layer per field
    parameters.layer_count = 2;
    parameters.progressive = 0;
    parameters.decompositor = DecomposeFields;
#endif
    
    RGB_IMAGE rgb_image;
    InitRGBImage(&rgb_image);

    vc5_buffer->buffer = encoding_parameters->mem_alloc( max_vc5_buffer_size );
    if (vc5_buffer->buffer == NULL) {
        return CODEC_ERROR_OUTOFMEMORY;
    }

    // Open a stream to the output file
    error = CreateStreamBuffer(&bitstream_file, vc5_buffer->buffer, max_vc5_buffer_size );
    if (error != CODEC_ERROR_OKAY) {
        ReleaseEncoderOutput(encoding_parameters, vc5_buffer, &rgb_image);
        return error;
    }

    // Encode the image into the byte stream
    error = EncodeImage(&image, &bitstream_file, &rgb_image, &parameters);
    if (error != CODEC_ERROR_OKAY) {
        ReleaseEncoderOutput(encoding_parameters, vc5_buffer, &rgb_image);
        return error;
    }
    
    // The stream stops storing at the end of the buffer but keeps counting, so a count past
    // the end means the bitstream was cut short
    if (bitstream_file.byte_count > max_vc5_buffer_size) {
        ReleaseEncoderOutput(encoding_parameters, vc5_buffer, &rgb_image);
        return CODEC_ERROR_FILE_WRITE;
    }

    if( rgb_buffer )
    {
        rgb_buffer->buffer  = rgb_image.buffer;
        rgb_buffer->size    = rgb_image.size;
        rgb_buffer->width   = rgb_image.width;
        rgb_buffer->height  = rgb_image.height;
    }
    
    vc5_buffer->size = bitstream_file.byte_count;
    
    return CODEC_ERROR_OKAY;
}
