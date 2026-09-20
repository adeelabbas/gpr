/*! @file main.cpp
 *
 *  @brief Main program file for the gpr_tools.
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

#include <stdio.h>
#include <string.h>

#include "argument_parser.h"

#include "gpr.h"
#include "gpr_buffer.h"
#include "gpr_print_utils.h"
#include "main_c.h"

#include "common_app_def.h"

using namespace std;

class my_argument_parser : public argument_parser
{
    bool    help;
    bool    verbose;

public:
    string  jpg_preview_file_path;

    bool    print_metadata;
    string  apply_metadata;

    string  input_path;
    int     input_width;
    int     input_height;
    int     input_pitch;
    string  input_pixel_format;
    int     input_skip_rows;

    string  output_path;

    string  gpmf_path;

    string  rgb_resolution;
    
    int     output_ppm_bits;

public:

    bool get_verbose() { return verbose; }
    
    bool get_help() { return help; }
    
    void set_options()
    {
        command_options.addOptions()
        /* long and short name */   /* variables */       /* default value */     /* help text */
        ("help",                    help,                 false,            "Prints this help text")
        
        ("verbose,v",               verbose,              false,            "Verbosity of the output")

        ("preview_file_path",       jpg_preview_file_path, string(""),      "Preview jpg file path")
        
        ("print_metadata,d",        print_metadata,       false,            "Print gpr params (as json) to standard output")
        ("apply_metadata,a",        apply_metadata,       string(""),       "Use gpr params for GPR/DNG metadata")

        ("input_path,i",            input_path,           string(""),       "Input file path \n"
                                                                            "File Choices: GPR, DNG, RAW")
        
        ("input_width,w",           input_width,          0,                "Input image width in pixel samples")
        ("input_height,h",          input_height,         0,                "Input image height in pixel samples")
        ("input_pitch,p",           input_pitch,          0,                "Input image pitch in bytes")
        ("input_pixel_format,x",    input_pixel_format,   string(""),       "Input pixel format \n"
                                                                            "Choices: rggb12, rggb12p, [rggb14], gbrg12, gbrg12p, bggr12, bggr14 \n")
        ("input_skip_rows",         input_skip_rows,      0,                "Input image rows to skip (shifts Bayer phase, e.g. BGGR->GRBG)")

        ("output_path,o",           output_path,          string(""),       "Output file path.\n"
                                                                            "File choices: GPR, DNG, PPM, RAW, JPG")
        ("gpmf_path,g",             gpmf_path,            string(""),       "GPMF file path")

        ("rgb_resolution",          rgb_resolution,       string(""),       "Output RGB resolution. Only applicable when output format is PPM or JPG \n"
                                                                            "Choices: 1:1, 2:1, [4:1], 8:1. 16:1")
        ("output_ppm_bits",         output_ppm_bits,      8,                "Output bits, use only with PPM output. Choices [8], 16")
        ;
    }
};

int dng_dump(const char*  input_file_path)
{
    gpr_allocator allocator;
    allocator.Alloc = malloc;
    allocator.Free = free;

    gpr_parameters params;

    gpr_parameters_set_defaults(&params);

    // Stream the metadata straight from the file; the image payload is never read
    int success = gpr_parameters_parse_dng_file( &allocator, input_file_path, &params );

    if( success )
    {
        gpr_parameters_print_json( &params, NULL );
    }
    else
    {
        fprintf( stderr, "Error while parsing file: %s \n", input_file_path );
    }

    return success ? 0 : -1;
}

int main(int argc, char *argv [])
{
    my_argument_parser args;
    
    
    char zerotag[MAX_STDOUT_LINE];
    sprintf(zerotag, "[%5d-ms] ", 0);

    char line[MAX_STDOUT_LINE];
    sprintf( line, "GPR Tools Version %d.%d.%d [%s @ %s] ", GPR_VERSION_MAJOR, GPR_VERSION_MINOR, GPR_VERSION_REVISION, GIT_BRANCH, GIT_COMMIT_HASH );
    
    if( args.parse(argc, argv, line, zerotag) )
    {
        printf("\n");
        printf("Following parameters override metadata when set and are only used when the input format is RAW: \n");
        printf("    input_width, input_height, input_pitch, input_pixel_format, input_skip_rows and input_skip_cols \n");
        printf("\n");
        printf("\n");
        printf("-- Example Commnads (please see data/tests/run_tests.sh for more examples) --\n");
        printf("GPR to DNG: \n");
        printf("  %s -i ./data/samples/HERO6.GPR -o ./data/samples/HERO6.DNG \n\n", argv[0] );
        printf("GPR to RGB (PPM format in 1000x750 resolution): \n");
        printf("  %s -i ./data/samples/HERO6.GPR -o ./data/samples/HERO6.PPM -r 4:1 \n\n", argv[0] );
        printf("GPR to RGB (JPG format in 500x375 resolution): \n");
        printf("  %s -i ./data/samples/HERO6.GPR -o ./data/samples/HERO6.JPG -r 8:1 \n\n", argv[0] );
        printf("Analyze a GPR or DNG file and output metadata parameters to a file: \n");
        printf("  %s -i ./data/samples/HERO6.GPR -d 1 > ./data/samples/HERO6.TXT \n\n", argv[0] );
        printf("Read RAW pixel data, along with gpr parameters (from a file) and apply to an output GPR or DNG file: \n");
        printf("  %s -i ./data/samples/HERO6.RAW -o ./data/samples/HERO6.DNG -a ./data/samples/HERO6.TXT \n\n", argv[0] );

        return -1;
    }
    
    if( args.print_metadata )
    {
        if( dng_dump(args.input_path.c_str()) != 0 )
            return -1;
    }
    else
    {
        string ext = strrchr( args.input_path.c_str(),'.');
        
        if( args.output_path == string("") && ( ext == string(".GPR") || ext == string(".gpr") ) )
        {
            args.output_path = args.input_path;
            args.output_path.erase(args.output_path.find_last_of("."), string::npos);
            
            args.output_path = args.output_path + string(".DNG");
        }
    }
    
    // We are not calling LogPrint here because that is an internal functionality to gpr_sdk
    fprintf( stderr, "%s Input File: %s \n",    zerotag, args.input_path.c_str() );
    fprintf( stderr, "%s Output File: %s \n",   zerotag, args.output_path.c_str() );

    if( args.output_path != "" )
    {
        dng_convert_params convert_params;
        convert_params.input_file_path         = args.input_path.c_str();
        convert_params.input_width             = args.input_width;
        convert_params.input_height            = args.input_height;
        convert_params.input_pitch             = args.input_pitch;
        convert_params.input_skip_rows         = args.input_skip_rows;
        convert_params.input_pixel_format      = args.input_pixel_format.c_str();
        convert_params.output_file_path        = args.output_path.c_str();
        convert_params.metadata_file_path      = args.apply_metadata.c_str();
        convert_params.gpmf_file_path          = args.gpmf_path.c_str();
        convert_params.rgb_file_resolution     = args.rgb_resolution.c_str();
        convert_params.rgb_file_bits           = args.output_ppm_bits;
        convert_params.jpg_preview_file_path   = args.jpg_preview_file_path.c_str();

        return dng_convert_main( &convert_params );
    }
    
    return 0;
}
    
