/*! @file rgb.h
 *
 *  @brief Handles conversion of wavelet to rgb format
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

#ifndef RGB_H
#define RGB_H

#include "types.h"
#include "pixel.h"
#include "image.h"
#include "gpr_rgb_buffer.h"

/*!
	@brief Parameters of the wavelet -> RGB conversion

	Everything WaveletToRGB needs to render RGB output, shared by the encoder
	(the RGB preview/thumbnail generated during encoding) and the decoder (the
	RGB output path), so both render with identical colors.
*/
typedef struct _rgb_parameters
{
    GPR_RGB_RESOLUTION  resolution;         //!< Resolution of the RGB output (or preview) relative to the full sensor.

    int                 bits;               //!< Bits per output RGB component: 8 (default) or 16

    gpr_rgb_gain        white_balance_gain; //!< White-balance gains applied after black-level subtraction

    int                 black_level;        //!< Sensor black level (16-bit linear RGB domain) subtracted before applying white_balance_gain

    float               color_matrix[3][3];  //!< Camera->linear-sRGB color matrix (row major), applied after rgb_gain; identity when no color profile is available

    float               baseline_exposure;  //!< DNG BaselineExposure (EV), applied as linear gain ahead of the tone curve; 0 = no adjustment

} RGB_PARAMETERS;

#ifdef __cplusplus
extern "C" {
#endif

    void rgb_parameters_set_default( RGB_PARAMETERS* rgb_params );

    void WaveletToRGB( gpr_allocator allocator, PIXEL* GS_src, PIXEL* RG_src, PIXEL* BG_src, DIMENSION src_width, DIMENSION src_height, DIMENSION src_pitch,
                       RGB_IMAGE *dst_image, int input_precision_bits, const RGB_PARAMETERS* rgb_params );

#ifdef __cplusplus
}
#endif

#endif // RGB_H
