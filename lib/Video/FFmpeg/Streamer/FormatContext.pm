package Video::FFmpeg::Streamer::FormatContext;

use Moose;
use namespace::autoclean;
use Video::FFmpeg::Streamer;
use Video::FFmpeg::Streamer::Stream;

use Carp qw/croak/;

=head1 NAME

Video::FFmpeg::Streamer::FormatContext - Represents a container format
encapsulating one or more encoders or decoders.
=head2 OPTIONS

=over 4

=item uri

Can be file name, "-" for STDOUT or a stream URI.

=cut
has 'uri' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
);


=item format

Format container type.

Required if format cannot be deduced from output file extension.

Can be file name, "-" for STDOUT or a stream URI.

=cut
has 'format' => (
    is => 'rw',
    isa => 'Str',
);


=item real_time

Do decoding in real-time. needed if attempting to stream recorded
video live, otherwise you will be streaming as fast as it can encode

=cut
has 'real_time' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);


# FFS_AVFormatCtx
has '_fmt' => (
    is => 'rw',
    required => 1,
);

# keep track of streamer object so we can get info from the input context
has 'streamer' => (
    is => 'ro',
    isa => 'Video::FFmpeg::Streamer',
    required => 1,
    weak_ref => 1,
    handles => [qw/input_format_context input_ctx debugging_enabled/],
);

# input stream objects. these are created automatically by
# get_stream() and saved
has 'input_streams' => (
    is => 'rw',
    isa => 'ArrayRef',
    lazy => 1,
    default => sub { [] },
);

# output streams are arrayrefs indexed by streamIndex
has 'output_streams' => (
    is => 'rw',
    isa => 'ArrayRef',
    lazy => 1,
    default => sub { [] },
);

=back

=head2 METHODS

=over 4


=item dump_format

Dump debugging info about this format context to stderr

=cut
sub dump_format {
    my ($self) = @_;

    Video::FFmpeg::Streamer::ffs_dump_format($self->_fmt, $self->uri);
}


=item set_metadata(key, value)

Add metadata to output container. Pass $value=undef to remove an item.

=cut
sub set_metadata {
    my ($self, $key, $value) = @_;
    
    Video::FFmpeg::FrameDecoder::ffs_set_ctx_metadata($self->_fmt, $key, $value);
}


=item add_audio_stream(\%options)

See L<Video::FFmpeg::Streamer::Stream> for options.

=cut
sub add_audio_stream {
    my ($self, $opts) = @_;

    $opts ||= {};
    $opts->{type} = 'audio';

    unless (defined $opts->{index}) {
        my $input_stream_index = $self->get_first_audio_stream_index;

        unless (defined $input_stream_index) {
            warn "Failed to add output audio stream - no audio input stream found.";
            return;
        }

        $opts->{index} = $input_stream_index;
    }

    $self->add_stream($opts);
}


=item add_video_stream(\%options)

See L<Video::FFmpeg::Streamer::Stream> for options.

=cut
sub add_video_stream {
    my ($self, $opts) = @_;

    $opts ||= {};
    $opts->{type} = 'video';

    unless (defined $opts->{index}) {
        my $input_stream_index = $self->get_first_video_stream_index;

        unless (defined $input_stream_index) {
            warn "Failed to add output video stream - no video input stream found.";
            return;
        }

        $opts->{index} = $input_stream_index;
    }

    $self->add_stream($opts);
}

sub add_stream {
    my ($self, $opts) = @_;

    my $index = $opts->{index};
    croak "Stream index is required" unless defined $index;

    my $input_stream = $self->streamer->input_ctx->get_stream($index);
    unless ($input_stream) {
        warn "Failed to find input stream at index $index. Cannot create corresponding output stream.\n";
        return;
    }

    my $output_stream;

    if ($input_stream->is_video_stream) {
        $output_stream = Video::FFmpeg::Streamer::Stream::Video->new($opts);
    } elsif ($input_stream->is_audio_stream) {
        $output_stream = Video::FFmpeg::Streamer::Stream::Audio->new($opts);
    } else {
        warn "Unknown stream type for index $index";
        return;
    }

    $self->output_streams->[$index] ||= [];
    my $output_streams = $self->output_streams->[$index];
    push @$output_streams, $output_stream;

    return $output_stream;
}

sub get_first_audio_stream_index {
    my ($self, $n) = @_;

    for (my $i = 0; $i < $self->stream_count; $i++) {
        next unless Video::FFmpeg::Streamer::ffs_is_audio_stream_index($self->_fmt, $i);
        return $i;
    }
    return undef;
}

sub get_first_video_stream_index {
    my ($self, $n) = @_;

    for (my $i = 0; $i < $self->stream_count; $i++) {
        next unless Video::FFmpeg::Streamer::ffs_is_video_stream_index($self->_fmt, $i);
        return $i;
    }
    return undef;
}

sub get_stream {
    my ($self, $index) = @_;

    croak "Attempting to get stream at index $index but there are only " . 
        $self->stream_count . "streams" if $index >= $self->stream_count;

    my $stream = $self->streams->[$index];
    unless ($stream) {
        my $avstream = Video::FFmpeg::Streamer::ffs_get_stream($self->_fmt, $index);
        croak "Unable to get stream at index $index" unless $avstream;

        $stream = Video::FFmpeg::Streamer::Stream->new(
            _stream => $avstream,
        );

        $self->streams->[$index] = $stream;
    }

    return $stream;
}

sub stream_count {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_stream_count($self->_fmt);
}

=item decode_frame

Reads a frame and streams it.

=cut
sub decode_frame {
    my ($self) = @_;

    # decode frame from input streams
    for (my $index = 0; $index < $self->stream_count; $index++) {
        # don't bother decoding input stream if there are no
        # corresponding output streams
        my $output_streams = $self->output_streams->[$index];
        next unless $output_streams;

        # get input stream
        my $input_stream = $self->get_stream($index);
        unless ($input_stream) {
            warn "Output streams exist for index $index but no input stream with that index was found";
            next;
        }

        # decode frame from input stream
        if ($input_stream->is_video_stream) {
            my $frame = $input_stream->decode_video_frame or next;

            # send frame to output streams to be encoded
            $_->encode_video_frame($frame) foreach @$output_streams;
        } elsif ($input_stream->is_audio_stream) {
            # decode frame from input stream
            my $frame = $input_stream->decode_audio_frame or next;

            # send frame to output streams to be encoded
            $_->encode_audio_frame($frame) foreach @$output_streams;
        }
    }
}

sub DEMOLISH {
    my ($self) = @_;

    Video::FFmpeg::Streamer::ffs_destroy_context($self->_fmt);
    warn "formatcontext destroyed";
}

__PACKAGE__->meta->make_immutable;

