package Video::FFmpeg::Streamer::Packet;

use Moose;
use namespace::autoclean;

use Video::FFmpeg::Streamer;

has 'avpacket' => (
    is => 'rw',
    isa => 'AVPacket',
    required => 1,
);

has 'success' => (
    is => 'rw',
    isa => 'Bool',
);

sub stream_index {
    my ($self) = @_;

    return unless $self->avpacket;
    return Video::FFmpeg::Streamer::ffs_get_avpacket_stream_index($self->avpacket);
}

sub DEMOLISH {
    my ($self) = @_;

    if ($self->avpacket) {
        Video::FFmpeg::Streamer::ffs_free_avpacket_data($self->avpacket);
    }
}

__PACKAGE__->meta->make_immutable;
