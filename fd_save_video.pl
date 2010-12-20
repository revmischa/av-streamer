#!/usr/bin/env perl

# This sample app captures and saves video from a video file
#   or stream.

# Options:
#   --framecount/-f N: only capture N frames
#   --output/-o: output file/stream name
#   --format/-of: output format
#   --bitrate/-b: birate
#   --debug/-d: turn out additional output

use Moose;
use Video::FFmpeg::FrameDecoder::App::SaveVideo;

#usage("Output file missing extension")
#    unless $out =~ /\.\w+$/ || $out =~ m!^\s*\w+://!;

my $gf = Video::FFmpeg::FrameDecoder::App::SaveFrames->new_with_options;

$gf->run;

sub usage {
    my ($err) = @_;
    die "$err\nUsage: $0 [--framecount N] [--debug] [--bitrate 400000] [-f FORMAT] -i input -o output\n";
}
