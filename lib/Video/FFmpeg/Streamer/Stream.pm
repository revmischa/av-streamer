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
    is => 'rw',
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
    predicate => 'has_avcodec_ctx',
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

# buffer to use for storing decoded audio/video frames
has 'output_buffer_size' => (
    is => 'rw',
    isa => 'Int',
    default => 1024*256,  # this is what ffmpeg uses
);
has '_output_buffer' => (
    is => 'rw',
    lazy => 1,
    predicate => 'has_output_buffer',
    builder => 'build_output_buffer',
);

# keep an avpacket around to speed up writing decoded frames
has '_output_avpacket' => (
    is => 'rw',
    isa => 'AVPacket',
    lazy => 1,
    predicate => 'has_output_avpacket',
    builder => 'build_output_avpacket',
);

has '_output_avframe' => (
    is => 'rw',
    lazy => 1,
    isa => 'AVFrame',
    predicate => 'has_output_avframe',
    builder => 'build_output_avframe',
);

# are we holding a reference to an existing stream or did we allocate
# memory for a new stream (and need to free it later)
has 'avstream_allocated' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

sub build_output_buffer {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_alloc_output_buffer($self->output_buffer_size);
}

sub build_output_avpacket {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_alloc_avpacket();
}

sub build_output_avframe {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_alloc_avframe();
}

sub create_avstream {
    my ($self, $istream) = @_;

    $self->destroy_stream;

    if (! $self->index_defined) {
        croak "Attempting to create stream without stream index defined";
    }

    my $codec_name = $self->codec_name
        or croak "Attempting to create stream without codec type defined";

    my $oavstream = Video::FFmpeg::Streamer::ffs_create_stream($self->format_ctx->avformat)
        or die "Failed to create new video stream for codec " . $self->codec_name;

    $self->avstream($oavstream);
    $self->avstream_allocated(1);

    return $oavstream;
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
    if ($self->is_video_stream) {
        $self->width(Video::FFmpeg::Streamer::ffs_get_codec_ctx_width($avcodec_ctx));
        $self->height(Video::FFmpeg::Streamer::ffs_get_codec_ctx_height($avcodec_ctx));
        $self->base_den(Video::FFmpeg::Streamer::ffs_get_codec_ctx_base_den($avcodec_ctx));
        $self->base_num(Video::FFmpeg::Streamer::ffs_get_codec_ctx_base_num($avcodec_ctx));
        $self->pixel_format(Video::FFmpeg::Streamer::ffs_get_codec_ctx_pixfmt($avcodec_ctx));
        $self->gop_size(Video::FFmpeg::Streamer::ffs_get_codec_ctx_gopsize($avcodec_ctx));
    } else {
        $self->channels(Video::FFmpeg::Streamer::ffs_get_codec_ctx_channels($avcodec_ctx));
        $self->sample_rate(Video::FFmpeg::Streamer::ffs_get_codec_ctx_sample_rate($avcodec_ctx));
    }
}

# write packet $ipkt, encoding video if necessary
sub write_packet {
    my ($self, $ipkt, $istream) = @_;

    my $oavformat = $self->format_ctx->avformat;
    my $oavpkt = $self->_output_avpacket;
    my $oavframe = $self->_output_avframe;
    Video::FFmpeg::Streamer::ffs_init_avpacket($oavpkt);

    my $ret;

    if ($self->needs_encoding) {
        # TRANSCODING: decode input packet into avframe structure,
        # then encode avframe as output packet

        # decode $ipkt into $oavframe
        my $status = $self->decode_packet($istream, $ipkt->avpacket, $oavframe);

        if ($status && $status > 0 && $oavframe) {
            # encode $oavframe into $oavpkt
            $ret = $self->encode_frame($oavframe, $oavpkt);

            if ($ret > 0) {
                # write packet to output
                $ret = Video::FFmpeg::Streamer::ffs_write_frame($oavformat, $oavpkt);
            }
        }
    } else {
        # copy input packet to output packet, updating pts/dts
        Video::FFmpeg::Streamer::ffs_raw_stream_packet($ipkt->avpacket, $oavpkt, $istream->avstream, $self->avstream);

        # write packet to output
        $ret = Video::FFmpeg::Streamer::ffs_write_frame($oavformat, $oavpkt);
    }
    
    Video::FFmpeg::Streamer::ffs_free_avpacket_data($oavpkt); # right??
    #Video::FFmpeg::Streamer::ffs_dealloc_avpacket($oavpkt); # av_free() works, av_freep doesnt, why?

    return $ret && $ret > -1;
}

sub decode_packet {
    my ($self, $pkt) = @_;

    
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
        Video::FFmpeg::Streamer::ffs_close_codec($self->avcodec_ctx)
            if $self->has_avcodec_ctx && $self->avcodec_ctx;

        $self->codec_open(0);
    }

    Video::FFmpeg::Streamer::ffs_dealloc_stream($self->avstream)
        if $self->avstream_exists && $self->avstream_allocated && $self->avstream;

    $self->clear_avstream;
    $self->avstream_allocated(0);
}

sub DEMOLISH {
    my ($self) = @_;

    Video::FFmpeg::Streamer::ffs_dealloc_avpacket($self->_output_avpacket)
        if $self->has_output_avpacket;

    Video::FFmpeg::Streamer::ffs_dealloc_avframe($self->_output_avframe)
        if $self->has_output_avframe;

    Video::FFmpeg::Streamer::ffs_dealloc_output_buffer($self->_output_buffer)
        if $self->has_output_buffer;

    $self->destroy_stream;
}

=back

=cut

__PACKAGE__->meta->make_immutable;

