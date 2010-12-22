package Video::FFmpeg::Streamer;

use 5.006000;

use Moose;
use namespace::autoclean;

use Video::FFmpeg::Streamer::FormatContext;

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('Video::FFmpeg::Streamer', $VERSION);


=head1 NAME

Video::FFmpeg::Streamer - Module to make transcoding, saving and
broadcasting AV streams simple.

=head1 SYNOPSIS

  use Moose;
  use Video::FFmpeg::Streamer;
  my $streamer = Video::FFmpeg::Streamer->new;

  # attempt to access a media stream or file path
  $streamer->open_uri('rtsp://10.0.1.2/mpeg4/media.amp')
      or die "Failed to open video stream";
  
  # dump some information about the stream to the console
  $streamer->dump_format;

  # create output format context, describing the output container
  # see L<Video::FFmpeg::Streamer::FormatContext> for options
  my $output1 = $streamer->add_output(
      uri => 'tcp://localhost:6666',
      format => 'flv',
      real_time => 0,
  );

  # add some stream metadata (in this case setting streamName for FLV)
  $output1->set_metadata('streamName', 'stream1');

  # add encoders for output stream
  # see L<Video::FFmpeg::Streamer::CodecContext> for options
  $output1->add_audio_stream({
      codec_name  => 'libfaac',
      sample_rate => 44_100,
      bit_rate    => 64_000,
      channels    => 2,
  });
  $output1->add_video_stream({
      codec_name => 'libx264',
      bit_rate   => 200_000,
  });

  # begin decoding input and streaming
  $streamer->stream;

  # streams closed automatically when object is destroyed
  # (can also call $streamer->close)
  undef $streamer;
  
=head1 DESCRIPTION

This module is based heavily on code from Max Vohra's Video::FFmpeg
and Martin Boehm's avcodec sample application. It is not an attempt to
create anything new or special, but rather to make a simple, moosified
structure to make manipulating streams easy for people unfamiliar with
FFmpeg or XS.

=head2 OPTIONS

=over 4

=cut


has 'input_format_context' => (
    is => 'rw',
    isa => 'Video::FFmpeg::Streamer::FormatContext',
    clearer => 'clear_input_format_context',
    predicate => 'has_input_format_context',
    handles => [qw/dump_format/],
);

has 'output_format_contexts' => (
    is => 'rw',
    isa => 'ArrayRef',
    lazy => 1,
    default => sub { [] },
    clearer => 'clear_output_format_contexts',
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

# output extra debugging information
has 'debug' => (
    is => 'rw',
    isa => 'Bool',
    default => 1,
    reader => 'debugging_enabled',
    writer => 'set_debugging_enabled',
);

sub debug {
    my ($self, $msg) = @_;

    return unless $self->debugging_enabled;
    print "FFmpeg::Video::Streamer: $msg\n";
    return undef;
}

=back

=head2 METHODS

=over 4

=cut


# alias to input ctx
sub input_ctx { $_[0]->input_format_context->avformat }

# takes path to file or stream URI
# returns context if success
sub open_uri {
    my ($self, $uri) = @_;

    my $fmt = ffs_open_uri($uri);
    if (! $fmt || ! ref $fmt) {
        $self->debug("Failed to open $uri");
        return;
    }

    my $fmt_ctx_obj = Video::FFmpeg::Streamer::FormatContext->new(
        avformat => $fmt,
        streamer => $self,
        uri      => $uri,
    );
    
    $self->input_format_context($fmt_ctx_obj);
    return $fmt_ctx_obj;
}

sub add_output {
    my ($self, %opts) = @_;

    $opts{streamer} = $self;

    my $output_fmt = Video::FFmpeg::Streamer::FormatContext->new(%opts);
    push @{$self->output_format_contexts}, $output_fmt;
    return $output_fmt;
}

sub close_input {
    my ($self) = @_;
    
    $self->clear_input_format_context;
}

sub close_outputs {
    my ($self) = @_;
    
    $self->clear_output_format_contexts;
}

sub DEMOLISH {
    my ($self) = @_;

    $self->close_input;
    $self->close_outputs;
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

=back

=cut

__PACKAGE__->meta->make_immutable;

__END__


=head1 SEE ALSO

=over 4

=item L<Video::FFmpeg>

=item L<http://web.me.com/dhoerl/Home/Tech_Blog/Entries/2009/1/22_Revised_avcodec_sample.c.html>

=back

=head1 AUTHOR

Mischa Spiegelmock, E<lt>revmischa@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Mischa Spiegelmock

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
