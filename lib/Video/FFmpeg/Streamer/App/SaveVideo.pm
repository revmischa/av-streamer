package Video::FFmpeg::FrameDecoder::App::SaveFrames;

use Moose;
    with 'MooseX::Getopt';
    with 'Video::FFmpeg::FrameDecoder::FrameHandler';
    
use namespace::autoclean;
use Carp qw/croak/;

use Video::FFmpeg::FrameDecoder;

has 'output_context' => (
    is => 'rw',
);

has 'output_video_stream' => (
    is => 'rw',
);

# create output context and output streams
after 'decoding_started' => sub {
    my ($self, $codec_ctx) = @_;

    my $output_context;

    # specify format shortname
    $output_context = Video::FFmpeg::FrameDecoder::ffv_fd_new_output_format_ctx($self->output_file_name, $self->output_format);
    unless ($output_context) {
        if ($self->output_format) {
            die "Failed to create context for format '" . $self->output_format . "'\n";
        } else {
            die "Unable to create an output context for " . $self->output_file_name . 
                ". Please specify a file name with a supported extension.\n";
        }
    }

    $self->output_context($output_context);

    my $bitrate = $self->dest_bitrate || $codec_ctx->bitrate;
    
    my $output_video_stream =
    Video::FFmpeg::FrameDecoder::ffv_fd_new_output_video_stream(
        $output_context,
        $codec_ctx->width,
        $codec_ctx->height,
        $bitrate,
        $codec_ctx->base_num,
        $codec_ctx->base_den,
        $codec_ctx->pixfmt,
        $codec_ctx->gopsize,
    );
    die "Unable to create output video stream for " . $self->output_file_name
        if ! $output_video_stream || ! ref $output_video_stream;

    $self->output_video_stream($output_video_stream);
    
    Video::FFmpeg::FrameDecoder::ffv_fd_write_header($output_context);
};

# clean up
after 'decoding_finished' => sub {
    my ($self, $codec_ctx) = @_;

    Video::FFmpeg::FrameDecoder::ffv_fd_write_trailer($self->output_context);

    Video::FFmpeg::FrameDecoder::ffv_fd_close_stream(
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

