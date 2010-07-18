#!/usr/bin/env perl

# This sample app captures and saves video from a video file
#   or stream.

# Options:
#   --frame_count N: only capture N frames
#   --debug: turn out additional output

use Moose;
use Video::FFmpeg::FrameDecoder::App::SaveVideo;

my $uri = shift @ARGV
    or die "$0: no input file specified\n";
    
my $out = shift @ARGV
    or die "$0: no output file specified.\n";
    
die "Output file missing extension\n"
    unless $out =~ /\.\w+$/;

my $gf = Video::FFmpeg::FrameDecoder::App::SaveFrames->new_with_options(
    stream_uri => $uri,
    file_name => $out,
);

$gf->run;
