package Video::FFmpeg::Streamer::App::Streamer;

use Moose;
    with 'MooseX::Getopt';
    
use namespace::autoclean;
use Carp qw/croak/;

use Video::FFmpeg::Streamer;

has 'streamer' => (
    is => 'rw',
    isa => 'Video::FFmpeg::Streamer',
    lazy_build => 1,
);

has 'input_uri' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
    cmd_flag => 'input_uri',
    cmd_aliases => 'i',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

has 'output_uri' => (
    is => 'rw',
    isa => 'Str',
    cmd_flag => 'output_uri',
    cmd_aliases => 'o',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

has 'output_format' => (
    is => 'rw',
    isa => 'Str',
    cmd_flag => 'output_format',
    cmd_aliases => 'f',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

has 'output_video_codec' => (
    is => 'rw',
    isa => 'Str',
    cmd_flag => 'output_vcodec',
    cmd_aliases => 'vcodec',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

has 'output_audio_codec' => (
    is => 'rw',
    isa => 'Str',
    cmd_flag => 'output_acodec',
    cmd_aliases => 'acodec',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

has 'real_time' => (
    is => 'rw',
    isa => 'Bool',
    cmd_flag => 'realtime',
    cmd_aliases => 'r',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

has 'debug' => (
    is => 'rw',
    isa => 'Bool',
    cmd_flag => 'debug',
    cmd_aliases => 'd',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

sub stream {
    my ($self) = @_;

    croak "Output URI not specified"
        unless $self->output_uri;

    # create streamer
    my $streamer = Video::FFmpeg::Streamer->new;
    $self->streamer($streamer);

    # open input file
    $streamer->open_uri($self->input_uri)
        or croak "Failed to open " . $self->input_uri;

    # input debugging info
    $streamer->dump_format if $self->debug;

    # create output format context
    my $output = $streamer->add_output(
        'uri' => $self->output_uri,
        'format' => $self->output_format,
        'real_time' => $self->real_time,
    );

    # create audio and video output streams

    # make sure input video stream exists if an output vcodec was requested
    my $vistream = $streamer->input_format_context->get_first_video_stream;
    if ($vistream) {
        # find first input video stream, add corresponding output stream
        # all done automatically for us!
        my $codec = $self->output_video_codec || 'copy';
        my $vostream = $output->add_video_stream({
            codec_name => $codec,
        });
    } elsif ($self->output_video_codec) {
        die "Output video codec " . $self->output_video_codec . " requested, but input file has no video streams.\n";
    }

    my $aistream = $streamer->input_format_context->get_first_audio_stream;
    if ($aistream) {
        # find first input audio stream, add corresponding output stream
        my $codec = $self->output_audio_codec || 'copy';
        my $aostream = $output->add_audio_stream({
            codec_name => $codec,
        });
    } elsif ($self->output_audio_codec) {
        die "Output audio codec " . $self->output_audio_codec . " requested, but input file has no audio streams.\n";
    }

    # input and output ready to stream
    print "Beginning streaming to " . $self->output_uri . "...\n" if $self->debug;

    $SIG{INT} = sub { $streamer->finish_streaming };

    $streamer->stream;

    print "Streaming finished\n" if $self->debug;
}

__PACKAGE__->meta->make_immutable;

