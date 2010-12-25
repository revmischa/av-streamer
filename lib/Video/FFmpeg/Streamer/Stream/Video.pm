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

has 'buffer_size' => (
    is => 'rw',
    isa => 'Int',
    default => 200_000,
    lazy => 1,
);

# write video packet $ipkt, encoding video if necessary
sub write_frame {
    my ($self, $ipkt, $istream) = @_;

    my $format_ctx = $self->format_ctx->avformat;

    my $oavpkt = Video::FFmpeg::Streamer::ffs_alloc_avpacket();
    Video::FFmpeg::Streamer::ffs_init_avpacket($oavpkt);

    if ($self->needs_encoding) {
        warn "need to video transcode";
        $self->encode_packet($ipkt);
    } else {
        Video::FFmpeg::Streamer::ffs_raw_stream_packet($ipkt->avpacket, $oavpkt, $istream->avstream, $self->avstream);
    }
    
    # write packet to output
    my $ret = Video::FFmpeg::Streamer::ffs_write_frame($format_ctx, $oavpkt);

    Video::FFmpeg::Streamer::ffs_free_avpacket_data($oavpkt); # right??
    Video::FFmpeg::Streamer::ffs_destroy_avpacket($oavpkt); # av_free() works, av_freep doesnt, why?

    return $ret > -1;
}

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
