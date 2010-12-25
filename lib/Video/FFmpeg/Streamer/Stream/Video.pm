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
    warn "writing packet $oavpkt";
    my $ret = Video::FFmpeg::Streamer::ffs_write_frame($format_ctx, $oavpkt);
    warn "write frame pkt ret=$ret";

    Video::FFmpeg::Streamer::ffs_free_avpacket($oavpkt); # ???
    Video::FFmpeg::Streamer::ffs_destroy_avpacket($oavpkt);

    return $ret > -1;
}

sub create_avstream {
    my ($self, $istream) = @_;

    $self->destroy_stream;

    if (! $self->index_defined) {
        croak "Attempting to create stream without stream index defined";
    }

    my $codec_name = $self->codec_name
        or croak "Attempting to create stream without codec type defined";

    my $oavstream = Video::FFmpeg::Streamer::ffs_create_video_stream($self->format_ctx->avformat)
        or die "Failed to create new video stream for codec " . $self->codec_name;

    if ($self->stream_copy) {
        my $ok = Video::FFmpeg::Streamer::ffs_copy_video_stream_params($self->format_ctx->avformat, $istream->avstream, $oavstream);
        die "Failed to copy stream params" unless $ok;
    } else {
        my $ok = Video::FFmpeg::Streamer::ffs_set_video_stream_params(
            $self->format_ctx->avformat,
            $oavstream,
            $codec_name,
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

    $self->avstream_allocated(1);

    return $oavstream;
}

__PACKAGE__->meta->make_immutable;
