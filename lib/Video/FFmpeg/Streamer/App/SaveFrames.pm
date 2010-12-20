package Video::FFmpeg::FrameDecoder::App::SaveFrames;

use Moose;
    with 'MooseX::Getopt';
    with 'Video::FFmpeg::FrameDecoder::FrameHandler';

use namespace::autoclean;

has 'file_name' => (
    is => 'rw',
    isa => 'Str',
    default => 'stream_capture',
    cmd_flag => 'name',
    cmd_aliases => 'n',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

sub frame_decoded {
    my ($self, $codec_ctx, $frame) = @_;
    
    my $frame_data = $frame->pixel_data;
    
    # write frame data to file
    my $fh;
    open($fh, '>', $self->file_name . '-' . $frame->seq_num . '.ppm')
        or die $!;
    
    # print frame header
    my $header = sprintf("P6\n%d %d\n255\n", $frame->width, $frame->height);
    syswrite($fh, $header);
    
    # print frame
    my $frame_size = $frame->frame_size;
    syswrite($fh, $frame_data, $frame_size);
    
    close $fh;
}

__PACKAGE__->meta->make_immutable;

