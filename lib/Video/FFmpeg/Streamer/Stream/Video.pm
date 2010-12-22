package Video::FFmpeg::Streamer::Stream::Video;

use Moose;
use namespace::autoclean;
use Video::FFmpeg::Streamer;

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
#    isa => 'Str',
#    default => 'PIX_FMT_YUV420P',
);

has 'buffer_size' => (
    is => 'ro',
    isa => 'Int',
    default => 200_000,
    lazy => 1,
);

sub build_avstream {
    my ($self) = @_;

    $self->destroy_stream;

    if (! $self->index_defined) {
        croak "Attempting to create stream without stream index defined";
    }

    my $codec_type = $self->codec_type
        or croak "Attempting to create stream without stream index defined";

    my $stream = Video::FFmpeg::Streamer::create_video_stream(
        $self->format_ctx->avformat,
        $self->codec_name,
        $self->stream_copy,
        $self->width,
        $self->height,
        $self->bit_rate,
        $self->base_num,
        $self->base_den,
        $self->gop_size,
        $self->pixel_format,
    );

    croak "Failed to create output video stream for codec " . $self->codec
        unless $stream;

    $self->avstream_allocated(1);

    return $stream;
}

__PACKAGE__->meta->make_immutable;
