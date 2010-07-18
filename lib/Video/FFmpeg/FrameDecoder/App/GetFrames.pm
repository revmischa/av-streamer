package Video::FFmpeg::FrameDecoder::App::GetFrames;

use Moose;
    with 'MooseX::Getopt';

use namespace::autoclean;
use Video::FFmpeg::FrameDecoder;

has 'frame_count' => (
    is => 'rw',
    isa => 'Int',
    default => 0,
);

has 'file_name' => (
    is => 'rw',
    isa => 'Str',
    default => 'stream_capture',
);

has 'stream_uri' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
);

has 'debug' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

sub run {
    my ($self) = @_;
    
    my $fd = Video::FFmpeg::FrameDecoder->new(debug => $self->debug);
    $fd->open_uri($self->stream_uri)
        or return;
        
    my $codec_ctx = $fd->open_video_stream_codec;
    $codec_ctx->start_decoding(callback => sub { $self->frame_decoded(@_) });
    $codec_ctx->decode_frames($self->frame_count);    
}

sub frame_decoded {
    my ($self, $frame) = @_;
    
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

