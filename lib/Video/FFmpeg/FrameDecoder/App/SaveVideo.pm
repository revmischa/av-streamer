package Video::FFmpeg::FrameDecoder::App::SaveFrames;

use Moose;
    with 'MooseX::Getopt';
    with 'Video::FFmpeg::FrameDecoder::FrameHandler';
    
use namespace::autoclean;
use Carp qw/croak/;

use Video::FFmpeg::FrameDecoder;

has 'file_name' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
);

has 'output_context' => (
    is => 'rw',
);

has 'output_video_stream' => (
    is => 'rw',
);

# create output context and output streams
after 'decoding_started' => sub {
    my ($self, $codec_ctx) = @_;
        
    my $output_context = 
    Video::FFmpeg::FrameDecoder::ffv_fd_new_output_format_ctx($self->file_name)
        or croak "Unable to create an output context for " . $self->file_name . 
        ". Please specify a file name with a supported extension.";
        
    $self->output_context($output_context);
    
    my $output_video_stream =
    Video::FFmpeg::FrameDecoder::ffv_fd_new_output_video_stream(
        $output_context,
        $codec_ctx->width,
        $codec_ctx->height,
        $codec_ctx->bitrate,
        $codec_ctx->rate_num,
#        $codec_ctx->rate_den,
        29,
        $codec_ctx->pixfmt,
        $codec_ctx->gopsize,
    );
    die "Unable to create output video stream for " . $self->file_name
        if ! $output_video_stream || ! ref $output_video_stream;

    $self->output_video_stream($output_video_stream);
    
    Video::FFmpeg::FrameDecoder::ffv_fd_write_header($output_context);
};

# clean up
after 'decoding_finished' => sub {
    my ($self, $codec_ctx) = @_;

    Video::FFmpeg::FrameDecoder::ffv_fd_write_trailer($self->output_context);

    Video::FFmpeg::FrameDecoder::ffv_fd_close_video_stream(
            $self->output_context,
            $self->output_video_stream,
    ) if $self->output_video_stream;
    
    Video::FFmpeg::FrameDecoder::ffv_fd_close_output_format_ctx($self->output_context)
         if $self->output_context;
};

sub frame_decoded {
    my ($self, $codec_ctx, $frame) = @_;
    
    #my $frame_data = $frame->pixel_data;
    my $frame_size = $frame->frame_size;

    # write frame to output stream
    Video::FFmpeg::FrameDecoder::ffv_fd_write_frame_to_output_video_stream(
        $self->output_context,
        $codec_ctx->codec_ctx,
        $self->output_video_stream,
        $frame->frame,
    );
}

__PACKAGE__->meta->make_immutable;

