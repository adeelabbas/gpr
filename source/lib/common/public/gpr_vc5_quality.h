/*! @file gpr_vc5_quality.h
 *
 *  @brief Quality settings of the VC-5 encoder, shared by the codec and the GPR SDK API.
 *
 *  gpr_parameters carries the setting in every build configuration, but the encoder
 *  library and its headers are only present when GPR_WRITING is on, so the enum lives
 *  here (a public common header) rather than in vc5_encoder.h.
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

#ifndef GPR_VC5_QUALITY_H
#define GPR_VC5_QUALITY_H

#ifdef __cplusplus
    extern "C" {
#endif

    /*!
     @brief Quality setting of the VC5 encoder: the quantizer table applied to the wavelet
     highpass bands, from the coarsest (LOW, smallest files) to the finest (ULTRA).
     */
    typedef enum
    {
        VC5_ENCODER_QUALITY_SETTING_LOW         = 0,		// Low (Lowest Quality)
        VC5_ENCODER_QUALITY_SETTING_MEDIUM      = 1,		// Medium
        VC5_ENCODER_QUALITY_SETTING_HIGH        = 2,		// High
        VC5_ENCODER_QUALITY_SETTING_FS1         = 3,		// Film Scan 1
        VC5_ENCODER_QUALITY_SETTING_FSX         = 4,		// Film Scan X
        VC5_ENCODER_QUALITY_SETTING_FS2         = 5,		// Film Scan 2 (Highest Quality)
        VC5_ENCODER_QUALITY_SETTING_ULTRA       = 6,        // Ultra (finer than Film Scan 2: largest files, highest fidelity)
        
        VC5_ENCODER_QUALITY_SETTING_COUNT       = 7,
        
        VC5_ENCODER_QUALITY_SETTING_DEFAULT     = VC5_ENCODER_QUALITY_SETTING_FSX,
        
    } VC5_ENCODER_QUALITY_SETTING;

#ifdef __cplusplus
    }
#endif

#endif // GPR_VC5_QUALITY_H
