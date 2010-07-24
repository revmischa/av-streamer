#!/usr/bin/env perl

# This sample app captures and saves frames from a video file
# or stream as uncompressed .ppm files

# Options:
#   --framecount/-f N: only capture N frames
#   --name/-n XYZ: prefix frames with XYZ-
#   --debug/-d: turn out additional output

use Moose;
use Video::FFmpeg::FrameDecoder::App::SaveFrames;

my $uri = shift @ARGV
    or die "Usage: $0 [--framecount N] [--name prefix] [--debug] /path/to/file\n";

my $gf = Video::FFmpeg::FrameDecoder::App::SaveFrames->new_with_options(
    stream_uri => $uri,
    dest_pix_format => 'PIX_FMT_RGB24',
);

$gf->run;
