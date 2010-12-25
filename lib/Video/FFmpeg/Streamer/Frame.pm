# This class represents a decoded frame
package Video::FFmpeg::FrameDecoder::Frame;

use Moose;
use namespace::autoclean;
use Video::FFmpeg::FrameDecoder;

has 'frame' => (
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

# return address of line of pixel data, it will be line_size bytes long
sub get_line {
    my ($self, $y) = @_;
    
    return Video::FFmpeg::FrameDecoder::ffv_fd_get_frame_line_pointer($self->frame, $y);
}

sub line_size {
    my ($self) = @_;
    
    return Video::FFmpeg::FrameDecoder::ffv_fd_get_line_size($self->frame, $self->width);
}

sub frame_size {
    my ($self) = @_;
    
    return Video::FFmpeg::FrameDecoder::ffv_fd_get_frame_size(
        $self->frame, $self->line_size, $self->height,
    );
}

sub pixel_data {
    my ($self) = @_;
    
    return Video::FFmpeg::FrameDecoder::ffv_fd_get_frame_data(
        $self->frame, $self->width, $self->height, $self->line_size, $self->frame_size,
    );
}

__PACKAGE__->meta->make_immutable;

