#!/usr/bin/env perl

# Sample application using AV::Streamer

use Moose;

use FindBin;
use lib "$FindBin::Bin/lib";

use AV::Streamer::App::Streamer;

###

my $s = AV::Streamer::App::Streamer->new_with_options;

# get output uri
unless ($s->output_uri) {
    my $extra = $s->extra_argv;
    die "No output file specified\n" unless $extra && $extra->[0];
    $s->output_uri($extra->[0]);
}

$s->stream;

