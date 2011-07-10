package AV::Streamer::Stream::Video;

use Moose;
use namespace::autoclean;
use AV::Streamer;
use AV::Streamer::Packet;

extends 'AV::Streamer::Stream';

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

# current PTS for syncronization
has 'clock' => (
    is => 'rw',
    isa => 'Num',
    default => sub { AV::Streamer::avs_no_pts_value() },
);

# decode $iavpkt into $oavframe
# returns < 0 on error
# returns undef if no error but frame not decoded (not enough data read to decode a frame yet)
sub decode_packet {
    my ($self, $istream, $iavpkt, $oavframe) = @_;

    my $fmt = $self->format_ctx->avformat;

    # read $iavpkt, if able to decode then it is stored in $oavframe
    # will return < 0 on error, 0 if not enough data was passed to decode a frame
    my $res = AV::Streamer::avs_decode_video_frame($fmt, $istream->avstream, $iavpkt, $oavframe);

    if ($res && ref $res) {
        # this shouldn't happen!
        warn "got ref! $res";
    }

    if ($res && $res < 0) {
        # failure... what to do?
        warn "failed to decode frame";
    }

    return $res;
}

# encode $iavframe into $oavpkt
sub encode_frame {
    my ($self, $istream, $ipkt, $iavframe, $oavpkt) = @_;

    # figure out our current PTS
    my $pts = $ipkt->scaled_pts($istream, $self->global_pts);
    $pts = AV::Streamer::avs_guess_correct_pts($self->pts_correction_ctx, $pts, $iavframe);

    warn "got pts: $pts";

    if ($pts) {
        # if we know our pts, set clock to it
        $self->clock($pts);
    } else {
        $pts = $self->clock;
    }

    # update the video clock
    my $frame_delay = $self->frame_delay;
    my $repeat_pict = AV::Streamer::avs_get_frame_repeat_pict($iavframe);
    # if we are repeating a frame, adjust clock accordingly
    $frame_delay += $repeat_pict * ($frame_delay * 0.5);
    $pts = $self->clock + $frame_delay;
    $self->clock($pts);

    my $res = AV::Streamer::avs_encode_video_frame($self->format_ctx->avformat, $self->avstream, $iavframe, $oavpkt, $self->_output_buffer, $self->output_buffer_size, $pts);

    if ($res < 0) {
        warn "failed to encode frame";
    }

    return $res;
}

# set stream video params after creation
after 'create_avstream' => sub {
    my ($self, $istream) = @_;

    my $oavstream = $self->avstream;

    if ($self->stream_copy) {
        my $ok = AV::Streamer::avs_copy_stream_params($self->format_ctx->avformat, $istream->avstream, $oavstream);
        die "Failed to copy stream params" unless $ok;
    } else {
        my $ok = AV::Streamer::avs_set_video_stream_params(
            $self->format_ctx->avformat,
            $oavstream,
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

        die "failed to set video stream params" unless $ok;
    }
};

__PACKAGE__->meta->make_immutable;
