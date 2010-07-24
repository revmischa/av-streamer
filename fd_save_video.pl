#!/usr/bin/env perl

# This sample app captures and saves video from a video file
#   or stream.

# Options:
#   --framecount/-f N: only capture N frames
#   --bitrate/-b N
#   --debug/-d: turn out additional output

use Moose;
use Video::FFmpeg::FrameDecoder::App::SaveVideo;

my $uri = shift @ARGV
    or usage("Error: no input file specified");
    
my $out = shift @ARGV
    or usage("Error: no output file specified.");
    
usage("Output file missing extension")
    unless $out =~ /\.\w+$/;

my $gf = Video::FFmpeg::FrameDecoder::App::SaveFrames->new_with_options(
    stream_uri => $uri,
    file_name => $out,
);

$gf->run;

sub usage {
    my ($err) = @_;
    die "$err\nUsage: $0 [--framecount N] [--debug] [--bitrate 400000] inputfile.ext outputfile.ext\n";
}