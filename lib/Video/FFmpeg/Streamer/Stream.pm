package Video::FFmpeg::Streamer::Stream;

use Moose;
use namespace::autoclean;
use Video::FFmpeg::Streamer;

use Carp qw/croak/;

=head1 NAME

Video::FFmpeg::Streamer::Stream - Represents an audio or video output
stream.

=cut

has 'avstream' => (
    is => 'ro',
    predicate => 'avstream_exists',
    clearer => 'clear_avstream',
);

has 'format_ctx' => (
    is => 'ro',
    isa => 'Video::FFmpeg::Streamer::FormatContext',
    required => 1,
    weak_ref => 1,
);

has 'index' => (
    is => 'ro',
    isa => 'Int',
    predicate => 'index_defined',
    lazy => 1,
    builder => 'build_index',
);

has 'codec_name' => (
    is => 'rw',
    isa => 'Str',
);

has 'avcodec_ctx' => (
    is => 'ro',
    isa => 'AVCodecContext',
    builder => 'build_codec_ctx',
    lazy => 1,
);

has 'bit_rate' => (
    is => 'rw',
    isa => 'Int',
);

has 'stream_copy' => (
    is => 'ro',
    isa => 'Bool',
    default => 0,
);

has 'codec_open' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

# are we holding a reference to an existing stream or did we allocate
# memory for a new stream (and need to free it later)
has 'avstream_allocated' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

sub create_avstream {
    my ($self) = @_;

    Carp::confess("Attempting to create new AVStream in the base class");
}

sub build_codec_ctx {
    my ($self) = @_;

    my $ctx = Video::FFmpeg::Streamer::ffs_get_codec_ctx($self->avstream);
    unless ($ctx) {
        warn "Failed to get codec context for AVStream " . $self->avstream;
        return;
    }
}

sub needs_encoding {
    my ($self) = @_;

    return 0 if $self->codec_name eq 'copy';
    return 0 if $self->stream_copy;
    return 1;
}

sub build_index {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_get_stream_index($self->avstream);
}

sub BUILD {
    my ($self) = @_;

    return unless $self->avstream_exists;

    $self->open_decoder;
}

# find stream codec and properties, open decoder
sub open_decoder {
    my ($self) = @_;

    return if $self->codec_open;

    my $avstream = $self->avstream;
    my $avcodec_ctx = $self->avcodec_ctx;

    # make sure we have a codec context
    unless ($avcodec_ctx) {
        warn "Expected to find AVCodecContext for stream";
        return;
    }

    # make sure we have a codec ID (should be already found from av_find_stream_info)
    my $codec_id = Video::FFmpeg::Streamer::ffs_get_stream_codec_id($self->avstream);
    unless ($codec_id) {
        warn "Failed to find codec ID for stream " . $self->avstream .
            ". Perhaps the codec format is unknown.";
        return;
    }

    unless (Video::FFmpeg::Streamer::ffs_open_decoder($avcodec_ctx, $codec_id)) {
        warn "Could not open decoder for AVStream " . $self->avstream . " codec ID $codec_id";
        return;
    }
    $self->codec_open(1);

    # extract info from the AVStream and codec context:
    $self->bit_rate(Video::FFmpeg::Streamer::ffs_get_codec_ctx_bitrate($avcodec_ctx));
    $self->codec_name(Video::FFmpeg::Streamer::ffs_get_codec_ctx_codec_name($avcodec_ctx));
    $self->width(Video::FFmpeg::Streamer::ffs_get_codec_ctx_width($avcodec_ctx));
    $self->height(Video::FFmpeg::Streamer::ffs_get_codec_ctx_height($avcodec_ctx));
    $self->base_den(Video::FFmpeg::Streamer::ffs_get_codec_ctx_base_den($avcodec_ctx));
    $self->base_num(Video::FFmpeg::Streamer::ffs_get_codec_ctx_base_num($avcodec_ctx));
    $self->pixel_format(Video::FFmpeg::Streamer::ffs_get_codec_ctx_pixfmt($avcodec_ctx));
    $self->gop_size(Video::FFmpeg::Streamer::ffs_get_codec_ctx_gopsize($avcodec_ctx));

    warn "opened decoder for codec name " . $self->codec_name;
}

=head2 METHODS

=over 4

=item is_video_stream

=cut
sub is_video_stream {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_is_video_stream($self->avstream);
}

=item is_audio_stream

=cut
sub is_audio_stream {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_is_audio_stream($self->avstream);
}

sub destroy_stream {
    my ($self) = @_;

    if ($self->codec_open) {
        Video::FFmpeg::Streamer::ffs_close_codec($self->avcodec_ctx);
        $self->codec_open(0);
    }

    Video::FFmpeg::Streamer::ffs_destroy_stream($self->avstream)
        if $self->avstream_exists && $self->avstream_allocated;

    $self->clear_avstream;
    $self->avstream_allocated(0);
}

sub DEMOLISH {
    my ($self) = @_;

    $self->destroy_stream;
}

=back

=cut

__PACKAGE__->meta->make_immutable;

