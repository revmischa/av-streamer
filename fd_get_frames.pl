#!/usr/bin/env perl

# This sample app captures and saves frames from a video file or stream
# Options:
#   --frame_count N: only capture N frames
#   --file_name ABC: prefix frames with ABC-
#   --debug: turn out additional output

use Moose;
use Video::FFmpeg::FrameDecoder::App::GetFrames;

my $uri = shift @ARGV
    or die "Usage: $0 /path/to/file";

my $gf = Video::FFmpeg::FrameDecoder::App::GetFrames->new_with_options(
    stream_uri => $uri,
);

$gf->run;
