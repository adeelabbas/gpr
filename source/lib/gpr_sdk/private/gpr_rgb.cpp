/*! @file gpr_rgb.c
 *
 *  @brief Implementation of top level functions that implement GPR-SDK API
 *
 *  GPR API can be invoked by simply including this header file.
 *  This file includes all other header files that are needed.
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

#include "gpr.h"
#include "gpr_rgb.h"
#include "stdc_includes.h"

// Matrix helpers below feed write_dng, which is compiled unconditionally because the
// DNG conversion API (gpr_convert_raw_to_dng and friends) does not depend on the VC5
// codec paths. They must stay outside the GPR_READING/GPR_WRITING guard.

static void multiply_3x3( const double a[3][3], const double b[3][3], double out[3][3] )
{
    int i, j;
    for ( i = 0; i < 3; i++ )
        for ( j = 0; j < 3; j++ )
            out[i][j] = a[i][0] * b[0][j] + a[i][1] * b[1][j] + a[i][2] * b[2][j];
}

/*!
 * 3x3 inverse via the adjugate. Returns false (out untouched) for a singular matrix.
 */
static bool invert_3x3( const double a[3][3], double inv[3][3] )
{
    double det = a[0][0] * ( a[1][1] * a[2][2] - a[1][2] * a[2][1] )
               - a[0][1] * ( a[1][0] * a[2][2] - a[1][2] * a[2][0] )
               + a[0][2] * ( a[1][0] * a[2][1] - a[1][1] * a[2][0] );
    if ( fabs( det ) < 1e-9 )
        return false;

    inv[0][0] =  ( a[1][1] * a[2][2] - a[1][2] * a[2][1] ) / det;
    inv[0][1] = -( a[0][1] * a[2][2] - a[0][2] * a[2][1] ) / det;
    inv[0][2] =  ( a[0][1] * a[1][2] - a[0][2] * a[1][1] ) / det;
    inv[1][0] = -( a[1][0] * a[2][2] - a[1][2] * a[2][0] ) / det;
    inv[1][1] =  ( a[0][0] * a[2][2] - a[0][2] * a[2][0] ) / det;
    inv[1][2] = -( a[0][0] * a[1][2] - a[0][2] * a[1][0] ) / det;
    inv[2][0] =  ( a[1][0] * a[2][1] - a[1][1] * a[2][0] ) / det;
    inv[2][1] = -( a[0][0] * a[2][1] - a[0][1] * a[2][0] ) / det;
    inv[2][2] =  ( a[0][0] * a[1][1] - a[0][1] * a[1][0] ) / det;
    return true;
}

void compute_xyz_to_camera_color_matrix( double in_matrix[3][3], double wb[3], double weight, double out_matrix[3][3] )
{
    double temp1[3][3];
    double temp2[3][3];

    int i,j;

    // Interpolate with identity matrix by weight w
    double w = weight;
    double z = 1.0 - weight;

    for (i = 0; i < 3; i++ )
    {
        for (j = 0; j < 3; j++ )
            temp1[i][j] = in_matrix[i][j] * w;

        temp1[i][i] += z;
    }

    // Multiply matrix by sRGB_to_XYZd50 (from http://www.brucelindbloom.com)
    static const double sRGB_to_XYZd50[3][3] = {{0.4361, 0.3851, 0.1431}, {0.2225, 0.7169, 0.0606}, {0.0139, 0.0971, 0.7142}};

    multiply_3x3( sRGB_to_XYZd50, temp1, temp2 );

    // Multiply on the right by diag(wb), i.e. scale column j by white balance gain j
    for (i = 0; i < 3; i++)
        for (j = 0; j < 3; j++)
            temp1[i][j] = temp2[i][j] * wb[j];
    
    // Invert the resulting matrix. A singular matrix (degenerate profile or zero wb
    // gains) falls back to identity rather than emitting NaN/Inf into the DNG tags.
    if ( !invert_3x3( temp1, out_matrix ) )
    {
        for (i = 0; i < 3; i++)
            for (j = 0; j < 3; j++)
                out_matrix[i][j] = ( i == j ) ? 1.0 : 0.0;
    }
}

