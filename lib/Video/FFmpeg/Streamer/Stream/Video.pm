package Video::FFmpeg::Streamer::Stream::Video;

use Moose;
use namespace::autoclean;
use Video::FFmpeg::Streamer;
use Video::FFmpeg::Streamer::Packet;

extends 'Video::FFmpeg::Streamer::Stream';

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

# decode $iavpkt into $oavframe
sub decode_packet {
    my ($self, $istream, $iavpkt, $oavframe) = @_;

    my $fmt = $self->format_ctx->avformat;

    # read $iavpkt, if able to decode then it is stored in $oavframe
    # will return < 0 on error, 0 if not enough data was passed to decode a frame
    my $res = Video::FFmpeg::Streamer::ffs_decode_video_frame($fmt, $istream->avstream, $iavpkt, $oavframe);

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
    my ($self, $iavframe, $oavpkt) = @_;

    my $res = Video::FFmpeg::Streamer::ffs_encode_video_frame($self->format_ctx->avformat, $self->avstream, $iavframe, $oavpkt, $self->_output_buffer, $self->output_buffer_size);

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
        my $ok = Video::FFmpeg::Streamer::ffs_copy_stream_params($self->format_ctx->avformat, $istream->avstream, $oavstream);
        die "Failed to copy stream params" unless $ok;
    } else {
        my $ok = Video::FFmpeg::Streamer::ffs_set_video_stream_params(
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
