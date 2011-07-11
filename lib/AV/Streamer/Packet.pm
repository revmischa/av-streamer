package AV::Streamer::Packet;

use Mouse;
use namespace::autoclean;

use AV::Streamer;

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
    return AV::Streamer::avs_get_avpacket_stream_index($self->avpacket);
}

sub dts {
    my ($self) = @_;

    return unless $self->avpacket;
    return AV::Streamer::avs_get_avpacket_dts($self->avpacket);
}

sub pts {
    my ($self) = @_;

    return unless $self->avpacket;
    return AV::Streamer::avs_get_avpacket_pts($self->avpacket);
}

sub DEMOLISH {
    my ($self) = @_;

    AV::Streamer::avs_dealloc_avpacket($self->avpacket);
}

__PACKAGE__->meta->make_immutable;
