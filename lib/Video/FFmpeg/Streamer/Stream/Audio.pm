package Video::FFmpeg::Streamer::Stream::Audio;

use Moose;
use namespace::autoclean;

extends 'Video::FFmpeg::Streamer::Stream';

use Carp qw/croak/;

has 'sample_rate' => (
    is => 'ro',
    isa => 'Int',
);

has 'channels' => (
    is => 'ro',
    isa => 'Int',
);

__PACKAGE__->meta->make_immutable;
