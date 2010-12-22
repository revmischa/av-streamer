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
    lazy => 1,
    builder => 'build_avstream',
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

has 'codec_ctx' => (
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

# are we holding a reference to an existing stream or did we allocate
# memory for a new stream (and need to free it later)
has 'avstream_allocated' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

sub build_avstream {
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

sub build_index {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_get_stream_index($self->avstream);
}

sub BUILD {
    my ($self) = @_;

    return unless $self->avstream_exists;

    # we are instantiating a new Stream and have an AVStream
    # this is an input stream and we need to open the decoder

    my $avstream = $self->avstream;
    my $avcodec_ctx = $self->codec_ctx;

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

    # extract info from the AVStream and codec context:
    $self->bit_rate(Video::FFmpeg::Streamer::ffs_get_codec_ctx_bitrate($avcodec_ctx));
    $self->codec_name(Video::FFmpeg::Streamer::ffs_get_codec_ctx_codec_name($avcodec_ctx));
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

    Video::FFmpeg::Streamer::ffs_destroy_stream($self->avstream)
        if $self->avstream_exists && $self->avstream_allocated;

    $self->clear_avstream;
    $self->avstream_allocated(0);

    warn "avstream destroyed";
}

sub DEMOLISH {
    my ($self) = @_;

    $self->destroy_stream;
}

=back

=cut

__PACKAGE__->meta->make_immutable;

