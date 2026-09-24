/*! @file logcurve.h
 *
 *  @brief Declaration of the data structures and constants used to do log conversion.
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

#ifndef LOGCURVE_H
#define LOGCURVE_H

#define LOG_CURVE_TABLE_LENGTH (1 << 12)

// Every unpack path in the encoder indexes EncoderLogCurve with a uint16_t input sample, or the
// sample shifted right, and nothing holds the sample to the pixel format's range (a DNG above its
// white level, a RAW whose high bits are set). The table covers the whole uint16_t range so no
// index can read past it; the entries past the 12-bit curve repeat its top value, so an
// out-of-range sample saturates at white.
#define ENCODER_LOG_CURVE_TABLE_LENGTH (1 << 16)

#ifdef __cplusplus
extern "C" {
#endif
    
	extern uint16_t EncoderLogCurve[];
	
	extern uint16_t DecoderLogCurve[];

	void SetupDecoderLogCurve(void);

    void SetupEncoderLogCurve(void);

#ifdef __cplusplus
}
#endif

#endif // LOGCURVE_H
