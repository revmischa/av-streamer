#!/usr/bin/env perl

# Sample application using Video::FFmpeg::Streamer

use Moose;

use FindBin;
use lib "$FindBin::Bin/lib";

use Video::FFmpeg::Streamer::App::Streamer;

###

my $s = Video::FFmpeg::Streamer::App::Streamer->new_with_options;

# get output uri
my $extra = $s->extra_argv;
die "No output file specified\n" unless $extra && $extra->[0];
$s->output_uri($extra->[0]);

$s->stream;

