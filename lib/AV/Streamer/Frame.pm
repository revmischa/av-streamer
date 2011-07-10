# This class represents a decoded frame
# (this is unused currently, right now we only deal in raw AVFrames. instantiating a new Frame each frame seems like a lot of overhead)
package AV::Streamer::Frame;

use Mouse;
use namespace::autoclean;
use AV::Streamer;

has 'avframe' => (
    is => 'rw',
    required => 1,
);

has 'width' => (
    is => 'rw',
    isa => 'Int',
    required => 1,
);

has 'height' => (
    is => 'rw',
    isa => 'Int',
    required => 1,
);

has 'seq_num' => (
    is => 'rw',
    isa => 'Int',
    required => 1,
);

# should this be repeated?
sub get_repeat_pict {
    my ($self) = @_;
    
    return AV::Streamer::avs_get_avframe_repeat_pict($self->avframe);
}

# return address of line of pixel data, it will be line_size bytes long
sub get_line {
    my ($self, $y) = @_;
    
    return AV::Streamer::avs_get_avframe_line_pointer($self->avframe, $y);
}

sub line_size {
    my ($self) = @_;
    
    return AV::Streamer::avs_get_line_size($self->avframe, $self->width);
}

sub frame_size {
    my ($self) = @_;
    
    return AV::Streamer::avs_get_avframe_size(
        $self->avframe, $self->line_size, $self->height,
    );
}

sub pixel_data {
    my ($self) = @_;
    
    return AV::Streamer::avs_get_avframe_data(
        $self->frame, $self->width, $self->height, $self->line_size, $self->frame_size,
    );
}

sub pts {
    my ($self) = @_;

    return AV::Streamer::avs_get_avframe_pts($self->frame);
}

__PACKAGE__->meta->make_immutable;


