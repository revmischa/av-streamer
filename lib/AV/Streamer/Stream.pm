package AV::Streamer::Stream;

use Mouse::Role;
use namespace::autoclean;
use AV::Streamer;

use Carp qw/cluck croak/;

requires 'create_output_avstream';
requires 'find_encoder';

=head1 NAME

AV::Streamer::Stream - Represents an audio or video output
stream.

=cut

has 'avstream' => (
    is => 'rw',
    predicate => 'avstream_exists',
    clearer => 'clear_avstream',
);

has 'format_ctx' => (
    is => 'ro',
    isa => 'AV::Streamer::FormatContext',
    required => 1,
    weak_ref => 1,
    handles => [qw/ global_pts /],
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
    predicate => 'has_avcodec_ctx',
);

has 'bit_rate' => (
    is => 'rw',
    isa => 'Int',
);

has 'stream_copy' => (
    is => 'ro',
    isa => 'Bool',
    lazy_build => 1,
);

has 'codec_open' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

# buffer to use for storing decoded audio/video frames
has 'output_buffer_size' => (
    is => 'rw',
    isa => 'Int',
    default => 1024*256,  # this is what ffmpeg uses
);
has '_output_buffer' => (
    is => 'rw',
    isa => 'AVSFrameBuffer',
    lazy => 1,
    predicate => 'has_output_buffer',
    builder => 'build_output_buffer',
);

has 'pts_correction_ctx' => (
    is => 'rw',
    isa => 'PtsCorrectionContext',
    lazy => 1,
    builder => 'build_pts_correction_ctx',
    predicate => 'pts_correction_ctx_exists',
);

# are we holding a reference to an existing stream or did we allocate
# memory for a new stream (and need to free it later)
has 'avstream_allocated' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

sub build_pts_correction_ctx {
    my ($self) = @_;

    return AV::Streamer::avs_alloc_and_init_pts_correction_context();
}

sub build_output_buffer {
    my ($self) = @_;

    return AV::Streamer::avs_alloc_output_buffer($self->output_buffer_size);
}

# creates an output AVStream with codec ready for encoding
sub create_encoder {
    my ($self, $istream) = @_;

    $self->destroy_stream;

    if (! $self->index_defined) {
        croak "Attempting to create stream without stream index defined";
    }

    my $codec_name = $self->codec_name;
    unless ($codec_name) {
        warn "No codec name specified, will attempt to guess default codec for output format\n";
    }

    my $codec = $self->find_encoder($codec_name);
    unless ($codec) {
        warn "failed to find encoder for " . ($codec_name || 'default');
        return;
    }
    
    my $oavstream = $self->create_output_avstream($istream, $codec)
        or return;

    # grab our codec context
    my $codec_ctx = AV::Streamer::avs_get_stream_codec_ctx($oavstream);
    unless ($codec_ctx) {
        warn "expected to find codec context in new output stream";
        return;
    }

    # stream created, encoder configured, ready to open the encoder
    unless (AV::Streamer::avs_open_encoder($codec_ctx, $codec)) {
        warn "failed to open codec";
        return;
    }

    # should be open for business now!

    $self->avstream($oavstream);
    $self->avstream_allocated(1);

    return $oavstream;
}

sub build_codec_ctx {
    my ($self) = @_;

    my $ctx = AV::Streamer::avs_get_codec_ctx($self->avstream);
    unless ($ctx) {
        warn "Failed to get codec context for AVStream " . $self->avstream;
        return;
    }
}

# are we just copying input codec data to output, or are we transcoding?
sub _build_stream_copy {    
    my ($self) = @_;

    return 1 if $self->codec_name eq 'copy';
    return 0;
}

# do we need to encode the stream data, or is it already encoded for
# us (stream copy)?
sub needs_encoding {
    my ($self) = @_;

    return $self->stream_copy ? 0 : 1;
}

sub build_index {
    my ($self) = @_;

    return AV::Streamer::avs_get_stream_index($self->avstream);
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
    my $codec_id = AV::Streamer::avs_get_stream_codec_id($self->avstream);
    unless ($codec_id) {
        warn "Failed to find codec ID for stream " . $self->avstream .
            ". Perhaps the codec format is unknown.";
        return;
    }

    unless (AV::Streamer::avs_open_decoder($avcodec_ctx, $codec_id)) {
        warn "Could not open decoder for AVStream " . $self->avstream . " codec ID $codec_id";
        return;
    }
    $self->codec_open(1);

    # extract info from the AVStream and codec context:
    $self->bit_rate(AV::Streamer::avs_get_codec_ctx_bitrate($avcodec_ctx));
    $self->codec_name(AV::Streamer::avs_get_codec_ctx_codec_name($avcodec_ctx));
    if ($self->is_video_stream) {
        $self->width(AV::Streamer::avs_get_codec_ctx_width($avcodec_ctx));
        $self->height(AV::Streamer::avs_get_codec_ctx_height($avcodec_ctx));
        $self->base_den(AV::Streamer::avs_get_stream_base_den($self->avstream));
        $self->base_num(AV::Streamer::avs_get_stream_base_num($self->avstream));
        $self->pixel_format(AV::Streamer::avs_get_codec_ctx_pixfmt($avcodec_ctx));
        $self->gop_size(AV::Streamer::avs_get_codec_ctx_gopsize($avcodec_ctx));
    } else {
        $self->channels(AV::Streamer::avs_get_codec_ctx_channels($avcodec_ctx));
        $self->sample_rate(AV::Streamer::avs_get_codec_ctx_sample_rate($avcodec_ctx));
    }
}

sub frame_delay {
    my ($self) = @_;

    return AV::Streamer::avs_get_codec_ctx_frame_delay($self->avcodec_ctx);
}

# write packet $ipkt, transcoding if necessary
# TODO: move decoding into a separate function, so we only
# need to decode once if we have multiple outputs
sub write_packet {
    my ($self, $ipkt, $istream, $decoded) = @_;

    my $oavformat = $self->format_ctx->avformat;
    my $oavpkt = AV::Streamer::avs_alloc_avpacket();
    
    my $ret;

    if ($self->needs_encoding) {
        # output avstream should already be created
        unless ($self->avstream_allocated && $self->avstream) {
            croak "output avstream has not been created, but we are trying to encode";
        }
        $ret = $self->encode_output($ipkt, $istream, $decoded, $oavpkt);
    } else {
        # copy input packet to output packet, updating pts/dts
        AV::Streamer::avs_raw_stream_packet($ipkt->avpacket, $oavpkt, $istream->avstream, $self->avstream);

        # write packet to output
        $ret = AV::Streamer::avs_write_frame($oavformat, $oavpkt);
    }

    AV::Streamer::avs_free_avpacket_data($oavpkt);
    AV::Streamer::avs_dealloc_avpacket($oavpkt);

    return $ret && $ret > -1;
}

=head2 METHODS

=over 4

=item is_video_stream

=cut
sub is_video_stream {
    my ($self) = @_;

    return AV::Streamer::avs_is_video_stream($self->avstream);
}

=item is_audio_stream

=cut
sub is_audio_stream {
    my ($self) = @_;

    return AV::Streamer::avs_is_audio_stream($self->avstream);
}

sub destroy_stream {
    my ($self) = @_;

    if ($self->codec_open) {
        AV::Streamer::avs_close_codec($self->avcodec_ctx)
            if $self->has_avcodec_ctx && $self->avcodec_ctx;

        $self->codec_open(0);
    }

    AV::Streamer::avs_dealloc_stream($self->avstream)
        if $self->avstream_exists && $self->avstream_allocated && $self->avstream;

    $self->clear_avstream;
    $self->avstream_allocated(0);
}

sub DEMOLISH {
    my ($self) = @_;
    
    AV::Streamer::avs_dealloc_output_buffer($self->_output_buffer)
        if $self->has_output_buffer && $self->_output_buffer;

    AV::Streamer::avs_destroy_pts_correction_context($self->pts_correction_ctx)
        if $self->pts_correction_ctx_exists && $self->pts_correction_ctx;

    $self->destroy_stream;
}

=back

=cut

#__PACKAGE__->meta->make_immutable;
1;

