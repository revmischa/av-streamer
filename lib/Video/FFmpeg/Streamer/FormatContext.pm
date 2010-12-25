package Video::FFmpeg::Streamer::FormatContext;

use Moose;
use namespace::autoclean;
use Video::FFmpeg::Streamer;
use Video::FFmpeg::Streamer::Stream;
use Video::FFmpeg::Streamer::Stream::Audio;
use Video::FFmpeg::Streamer::Stream::Video;
use Video::FFmpeg::Streamer::OutputFormat;

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

# have we managed to open the output file yet?
has 'output_opened' => (
    is => 'rw',
    isa => 'Bool',
);

# did we open an input file for reading?
has 'input_opened' => (
    is => 'rw',
    isa => 'Bool',
);

# FFS_AVFormatCtx
# required if is input stream
has 'avformat' => (
    is => 'rw',
    isa => 'AVFormatContext',
    lazy => 1,
    builder => 'build_avformat_ctx',
    predicate => 'avformat_exists',
);

has 'output_format' => (
    is => 'rw',
    isa => 'Video::FFmpeg::Streamer::OutputFormat',
    clearer => 'clear_output_format',
);

# keep track of streamer object so we can get info from the input context
has 'streamer' => (
    is => 'ro',
    isa => 'Video::FFmpeg::Streamer',
    required => 1,
    weak_ref => 1,
    handles => [qw/input_format_context input_ctx debugging_enabled/],
);

# output streams are arrayrefs indexed by streamIndex
has 'streams' => (
    is => 'rw',
    isa => 'ArrayRef',
    lazy => 1,
    default => sub { [] },
);

# pre-allocated avpacket used to store current frame
has 'avpacket' => (
    is => 'rw',
    isa => 'AVPacket',
    lazy => 1,
    builder => 'build_avpacket',
    predicate => 'avpacket_exists',
);

=back

=head2 METHODS

=over 4

=cut



# allocate an AVPacket for saving packets read from input
sub build_avpacket {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_alloc_avpacket();
}

# create avformatctx, open output file
sub build_avformat_ctx {
    my ($self) = @_;

    if ($self->output_opened) {
        # TODO: should gracefully handle building a new format ctx
        warn "Building new avformat ctx but we have already opened output file!";
    }

    my $uri = $self->uri;
    $uri = 'pipe:' if $uri eq '-';

    # get output format
    $self->clear_output_format;
    my $ofmt = Video::FFmpeg::Streamer::OutputFormat->find_output_format($self->uri, $self->format);
    unless ($ofmt) {
        my $err = "Unable to open output '$uri'";
        $err .= " with format " . $self->format if $self->format;
        $err .= ". Please specify a recognized file extension or format name.";
        warn "$err\n";
        return;
    }

    $self->output_opened(0);

    # attempt to open output
    my $fmt = Video::FFmpeg::Streamer::ffs_create_output_format_ctx($ofmt->ofmt, $uri);
    unless ($fmt) {
        die "Unable to open output $uri\n";
    }

    $self->output_opened(1);
    $self->output_format($ofmt);
    $self->avformat($fmt);

    return $fmt;
}


=item dump_format

Dump debugging info about this format context to stderr

=cut
sub dump_format {
    my ($self) = @_;

    Video::FFmpeg::Streamer::ffs_dump_format($self->avformat, $self->uri);
}


=item set_metadata(key, value)

Add metadata to output container. Pass $value=undef to remove an item.

=cut
sub set_metadata {
    my ($self, $key, $value) = @_;
    
    Video::FFmpeg::Streamer::ffs_set_ctx_metadata($self->avformat, $key, $value);
}


=item add_audio_stream(\%options)

See L<Video::FFmpeg::Streamer::Stream> for options.

=cut
sub add_audio_stream {
    my ($self, $opts) = @_;

    $opts ||= {};
    $opts->{type} = 'audio';

    unless (defined $opts->{index}) {
        my $input_stream_index = $self->input_format_context->get_first_audio_stream_index;

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
        my $input_stream_index = $self->input_format_context->get_first_video_stream_index;

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

    my $input_stream = $self->streamer->input_format_context->get_stream($index);
    unless ($input_stream) {
        warn "Failed to find input stream at index $index. Cannot create corresponding output stream.\n";
        return;
    }

    my $output_stream;

    $opts->{format_ctx}   = $self;
    $opts->{bit_rate}   ||= $input_stream->bit_rate;

    if ($opts->{codec_name} && lc $opts->{codec_name} eq 'copy') {
        $opts->{stream_copy} = 1;
    }

    $opts->{codec_name} ||= $input_stream->codec_name;

    my $stream_class;

    # set default params from input, not used if codec=copy
    {
        my @stream_params;

        # prepare output stream
        if ($input_stream->is_video_stream) {
            @stream_params = qw/width height gop_size base_num base_den pixel_format/;
            $stream_class = 'Video::FFmpeg::Streamer::Stream::Video';
        } elsif ($input_stream->is_audio_stream) {
            @stream_params = qw/channels sample_rate/;
            $stream_class = 'Video::FFmpeg::Streamer::Stream::Audio';
        } else {
            warn "Unknown stream type for index $index";
            return;
        }

        # copy stream params from input to output
        foreach my $param (@stream_params) {
            my $val = $input_stream->$param;
            next unless defined $val;
            $opts->{$param} ||= $val;
        }
    }

    $output_stream = $stream_class->new($opts);
    $output_stream->create_avstream($input_stream);

    $self->streams->[$index] ||= [];
    my $streams = $self->streams->[$index];
    push @$streams, $output_stream;

    return $output_stream;
}

sub get_first_audio_stream_index {
    my ($self, $n) = @_;

    for (my $i = 0; $i < $self->stream_count; $i++) {
        next unless Video::FFmpeg::Streamer::ffs_is_audio_stream_index($self->avformat, $i);
        return $i;
    }
    return undef;
}

sub get_first_video_stream_index {
    my ($self, $n) = @_;

    for (my $i = 0; $i < $self->stream_count; $i++) {
        next unless Video::FFmpeg::Streamer::ffs_is_video_stream_index($self->avformat, $i);
        return $i;
    }
    return undef;
}

sub get_stream {
    my ($self, $index) = @_;

    croak "Attempting to get stream at index $index but there are only " . 
        $self->stream_count . " streams" if $index >= $self->stream_count;

    my $stream = $self->streams->[$index];
    unless ($stream) {
        my $avstream = Video::FFmpeg::Streamer::ffs_get_stream($self->avformat, $index);
        croak "Unable to get stream at index $index" unless $avstream;

        if (Video::FFmpeg::Streamer::ffs_is_video_stream($avstream)) {
            $stream = Video::FFmpeg::Streamer::Stream::Video->new(
                format_ctx => $self,
                avstream   => $avstream,
            );
        } elsif (Video::FFmpeg::Streamer::ffs_is_audio_stream($avstream)) {
            $stream = Video::FFmpeg::Streamer::Stream::Audio->new(
                format_ctx => $self,
                avstream   => $avstream,
            );
        } else {
            warn "Unknown stream type for index $index";
            return;
        }

        $self->streams->[$index] = $stream;
    }

    return $stream;
}

# read one frame, returns $packet
sub read_frame {
    my ($self) = @_;

    my $format_ctx = $self->avformat;
    my $pkt = $self->avpacket;
    my $ret = Video::FFmpeg::Streamer::ffs_read_frame($format_ctx, $pkt);

    warn "decode frame pkt=$pkt ret=$ret";

    my $retpkt = Video::FFmpeg::Streamer::Packet->new(
        avpacket => $pkt,
        success  => ($ret > -1),
    );

    return $retpkt;
}

sub stream_count {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_stream_count($self->avformat);
}

sub write_header {
    my ($self) = @_;

    warn "writing header for format " . $self->avformat;
    return Video::FFmpeg::Streamer::ffs_write_header($self->avformat);
}

sub write_trailer {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_write_trailer($self->avformat);
}

sub DEMOLISH {
    my ($self) = @_;

    Video::FFmpeg::Streamer::ffs_destroy_avpacket($self->avpacket)
        if $self->avpacket_exists;

    Video::FFmpeg::Streamer::ffs_close_input_file($self->avformat)
        if $self->input_opened;

#    Video::FFmpeg::Streamer::ffs_destroy_context($self->avformat)
#        if $self->avformat_exists;
}

=back

=cut

__PACKAGE__->meta->make_immutable;

