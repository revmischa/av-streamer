package AV::Streamer::Packet;

use Moose;
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

sub raw_dts {
    my ($self) = @_;

    return unless $self->avpacket;
    return AV::Streamer::avs_get_avpacket_dts($self->avpacket);
}

# returns PTS scaled to stream's timebase. uses $global_pts if unable to determine packet's DTS
sub scaled_pts {
    my ($self, $stream, $global_pts) = @_;

    return unless $self->avpacket;
    return AV::Streamer::avs_get_avpacket_scaled_pts($self->avpacket, $stream->avstream, $global_pts);
}

sub DEMOLISH {
    my ($self) = @_;

    # we don't need to destroy avpacket because it's passed in from
    # elsewhere. the user of this library takes responsibility for
    # the packet, allowing us to reuse an allocated packet.
}

__PACKAGE__->meta->make_immutable;
