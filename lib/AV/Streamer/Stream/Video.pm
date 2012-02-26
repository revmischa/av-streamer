package AV::Streamer::Stream::Video;

use Mouse;
use namespace::autoclean;
use AV::Streamer;
use AV::Streamer::Packet;

with 'AV::Streamer::Stream';

use Carp qw/croak/;

has 'width' => (
    is => 'rw',
    isa => 'Int',
);

has 'height' => (
    is => 'rw',
    isa => 'Int',
);

has 'gop_size' => (
    is => 'rw',
    isa => 'Int',
);

has 'base_num' => (
    is => 'rw',
    isa => 'Int',
);

has 'base_den' => (
    is => 'rw',
    isa => 'Int',
);

has 'pixel_format' => (
    is => 'rw',
#    isa => 'Str',
#    default => 'PIX_FMT_YUV420P',
);

# free avframe
sub free_decoded {
    my ($self, $avframe) = @_;

    return unless $avframe;

    AV::Streamer::avs_dealloc_avframe($avframe);    
}

# encodes iframe and writes it out
sub encode_output {
    my ($self, $ipkt, $istream, $iframe, $oavpkt) = @_;

    my $status = $self->encode_frame($istream, $ipkt, $iframe, $oavpkt);
    return unless $status;
    
    return AV::Streamer::avs_write_frame($self->format_ctx->avformat, $oavpkt);
}

# decode $iavpkt into $oavframe
# returns ($status, $oavframe)
# caller is responsible for calling $istream->free_decoded($oavframe) when done with it
# status < 0 on error
# status == undef if no error but frame not decoded (not enough data read to decode a frame yet)
sub decode_packet {
    my ($self, $istream, $iavpkt) = @_;

    my $oavframe = AV::Streamer::avs_alloc_avframe();
    my $fmt = $self->format_ctx->avformat;

    # read $iavpkt, if able to decode then it is stored in $oavframe
    # will return < 0 on error, 0 if not enough data was passed to decode a frame
    my $res = AV::Streamer::avs_decode_video_frame($fmt, $istream->avstream, $iavpkt, $self->pts_correction_ctx, $oavframe);

    if ($res && ref $res) {
        # this shouldn't happen!
        warn "got ref! $res";
    }

    # failed to decode
    if ($res && $res < 0) {
        AV::Streamer::avs_dealloc_avframe($oavframe);
        return ($res);
    }

    # didn't get a frame
    unless ($res) {
        AV::Streamer::avs_dealloc_avframe($oavframe);
        return ($res);
    }

    return ($res, $oavframe);
}

# encode $iavframe into $oavpkt
sub encode_frame {
    my ($self, $istream, $ipkt, $iavframe, $oavpkt) = @_;

    croak "encode_frame called but no output stream has been created"
        unless $self->avstream;
    
    # get PTS and scale for output timebase
    my $pts = AV::Streamer::avs_get_avframe_pts($iavframe);
    $pts = AV::Streamer::avs_scale_pts($pts, $self->avstream);
    
    # if we are repeating a frame, adjust clock accordingly
    my $frame_delay = $self->frame_delay;
    my $repeat_pict = AV::Streamer::avs_get_avframe_repeat_pict($iavframe);
    $frame_delay += $repeat_pict * ($frame_delay * 0.5);
    $pts = $pts + $frame_delay;

    # encode $iavframe into $oavpkt
    my $res = AV::Streamer::avs_encode_video_frame($self->format_ctx->avformat, $self->avstream, $iavframe, $oavpkt, $self->_output_buffer, $self->output_buffer_size, $pts);

    if ($res) {
        warn "failed to encode frame";
    }

    return $res;
}

sub find_encoder {
    my ($self, $istream, $codec_name) = @_;

    my $fmt_ctx = $self->format_ctx->avformat;
    
    my $codec;
    if ($self->stream_copy) {
        # jack the codec from the input stream
        $codec = AV::Streamer::avs_get_stream_codec($istream->avstream);
    }

    # look up by codec name
    $codec ||= AV::Streamer::avs_find_video_encoder($fmt_ctx, $codec_name)
       if $codec_name;
    
    # last resort - try default
    $codec ||= AV::Streamer::avs_find_video_encoder($fmt_ctx, undef);

    return $codec;
}

sub create_output_avstream {
    my ($self, $istream, $codec) = @_;

    my $fmt_ctx = $self->format_ctx->avformat;

    # creates output stream and associated codec context
    my $oavstream = AV::Streamer::avs_create_output_video_stream(
        $self->format_ctx->avformat,
        $codec,
    ) or return;

    # set our encoder params
    if ($self->stream_copy) {
        my $ok = AV::Streamer::avs_copy_stream_params($self->format_ctx->avformat, $istream->avstream, $oavstream);
        die "Failed to copy stream params" unless $ok;
    } else {
        warn "base num: " . $self->base_num . " base den: " . $self->base_den;
        my $ok = AV::Streamer::avs_set_video_stream_params(
            $self->format_ctx->avformat,
            $oavstream,
            $self->width,
            $self->height,
            $self->bit_rate,
            $self->base_num,
            $self->base_den,
            $self->gop_size,
            $self->pixel_format,
        );

        die "failed to set video stream params" unless $ok;
    }

    return $oavstream;
};

__PACKAGE__->meta->make_immutable;
