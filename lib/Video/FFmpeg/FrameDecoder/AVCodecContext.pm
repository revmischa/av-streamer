package Video::FFmpeg::FrameDecoder::AVCodecContext;

use Moose;
use namespace::autoclean;
use Video::FFmpeg::FrameDecoder;

use Carp qw/croak/;

has 'codec_ctx' => (
    is => 'rw',
    required => 1,
);

has 'format_ctx' => (
    is => 'rw',
    required => 1,
);

has 'stream_index' => (
    is => 'rw',
    isa => 'Int',
    required => 1,
);

# frame structure for the source native frame. probably YUV 420
has 'source_frame' => (
    is => 'rw',
    builder => 'alloc_frame',
    lazy => 1,
    predicate => 'source_frame_allocated',
);

# frame structure for the decoded frame, RGB
has 'dest_frame' => (
    is => 'rw',
    builder => 'alloc_frame',
    lazy => 1,
    predicate => 'dest_frame_allocated',
);

# storage for RGB24 decoding buffer
has 'frame_decode_buffer' => (
    is => 'rw',
    predicate => 'frame_decode_buffer_allocated',
);

# is storage allocated for decoding?
has 'decoding_prepared' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

# coderef to call when a frame is decoded
has 'frame_decode_callback' => (
    is => 'rw',
    isa => 'CodeRef',
);

# FrameHandler instance which will have 
# ->frame_decoded() when a frame is decoded
has 'frame_decode_delegate' => (
    is => 'rw',
    does => 'Video::FFmpeg::FrameDecoder::FrameHandler',
);


# start decoding frames
# opts: callback, delegate
# calls optional $callback on each frame, also calls ->frame_decoded() on $delegate
sub start_decoding {
    my ($self, %opts) = @_;
    
    my $callback = delete $opts{callback};
    my $delegate = delete $opts{delegate};
    
    if ($delegate && ! $delegate->does('Video::FFmpeg::FrameDecoder::FrameHandler')) {
        croak "Delegate $delegate does not implement the FrameHandler role";
    }
    
    croak "Unknown opts: " . join(', ', keys %opts) if keys %opts;
        
    $self->frame_decode_delegate($delegate) if $delegate;
    $self->frame_decode_callback($callback) if $callback;
    
    $self->prepare_video_frame_decoding;
}

# decode $frame_count frames and call callbacks.
# should be called after $start_decoding
sub decode_frames {
    my ($self, $frame_count) = @_;
    
    return unless $frame_count;

    $self->prepare_video_frame_decoding;
    
    my $decoded_cb = $self->frame_decode_callback;
    my $decoded_delegate = $self->frame_decode_delegate;
    
    # this is called each time a frame is decoded
    my $decoded = sub {
        my ($frame) = @_;
                
        $decoded_cb->($frame) if $decoded_cb;
        $decoded_delegate->frame_decoded($frame) if $decoded_delegate;
    };
    
    # mega awesome frame decoding function
    return Video::FFmpeg::FrameDecoder::ffv_fd_decode_frames(
        $self->format_ctx,
        $self->codec_ctx,
        $self->stream_index,
        
        $self->source_frame,
        $self->dest_frame,
        $self->frame_decode_buffer,
        
        $frame_count,
        $decoded,
    );
}

# allocate buffer and frames for decoding video frames to RGB
sub prepare_video_frame_decoding {
    my ($self) = @_;
    
    return if $self->decoding_prepared;

    # allocate frame structures
    my $src_frame = Video::FFmpeg::FrameDecoder::ffv_fd_alloc_frame();
    my $dst_frame = Video::FFmpeg::FrameDecoder::ffv_fd_alloc_frame();
    $self->source_frame($src_frame);
    $self->dest_frame($dst_frame);
    
    # allocate storage for RGB frame decoding buffer
    my $frame_decode_buffer = Video::FFmpeg::FrameDecoder::ffv_fd_alloc_frame_buffer(
        $self->codec_ctx,
        $dst_frame,
    );
    $self->frame_decode_buffer($frame_decode_buffer);
    
    $self->decoding_prepared(1);
}

# dellocate storage
sub finish_video_frame_decoding {
    my ($self) = @_;
    
    # release allocated frames
    {
        Video::FFmpeg::FrameDecoder::ffv_fd_dealloc_frame($self->source_frame)
            if $self->source_frame_allocated;

        Video::FFmpeg::FrameDecoder::ffv_fd_dealloc_frame($self->dest_frame)
            if $self->dest_frame_allocated;
    }

    # release frame decoding buffer
    if ($self->frame_decode_buffer_allocated) {
        Video::FFmpeg::FrameDecoder::ffv_fd_dealloc_frame_buffer($self->frame_decode_buffer);
    }

    # close codec
    Video::FFmpeg::FrameDecoder::ffv_fd_close_codec($self->codec_ctx);
    
    $self->decoding_prepared(0);
}

sub DEMOLISH {
    my ($self) = @_;
    
    $self->finish_video_frame_decoding;
}

__PACKAGE__->meta->make_immutable;

