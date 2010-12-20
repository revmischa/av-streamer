package Video::FFmpeg::Streamer::Stream::Video;

use Moose;
use namespace::autoclean;

extends 'Video::FFmpeg::Streamer::Stream';

use Carp qw/croak/;

has 'width' => (
    is => 'ro',
    isa => 'Int',
);

has 'height' => (
    is => 'ro',
    isa => 'Int',
);

has 'gop_size' => (
    is => 'ro',
    isa => 'Int',
);

has 'pixel_format' => (
    is => 'rw',
    isa => 'Str',
    default => 'PIX_FMT_YUV420P',
);

has 'buffer_size' => (
    is => 'ro',
    isa => 'Int',
    default => 200_000,
    lazy => 1,
);

__PACKAGE__->meta->make_immutable;
