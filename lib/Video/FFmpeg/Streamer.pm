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
      or die "Failed to open stream";
  
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
libav or XS.

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

Do decoding in real-time. needed if attempting to stream a recorded
video file live. If not specified you will be streaming as fast as the
input file can be transcoded.

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

has 'finished_streaming' => (
    is => 'rw',
    isa => 'Bool',
);

sub debug {
    my ($self, $msg) = @_;

    return unless $self->debugging_enabled;
    print "FFmpeg::Video::Streamer: $msg\n";
    return undef;
}

sub finish_streaming {
    my ($self) = @_;
    $self->finished_streaming(1);
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
        avformat     => $fmt,
        streamer     => $self,
        uri          => $uri,
        input_opened => 1,
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

=item stream

Streams from input stream to output streams

=cut
sub stream {
    my ($self) = @_;

    $_->write_header for @{ $self->output_format_contexts };

    $self->finished_streaming(0);
    while ($self->stream_frame && ! $self->finished_streaming) {
        # loop until finished
    }

    $_->write_trailer for @{ $self->output_format_contexts };
}

=item stream_frame

Reads a frame from input and encodes it to output streams

=cut
sub stream_frame {
    my ($self) = @_;

    my $pkt = $self->input_format_context->read_packet;
    if (! $pkt->success) {
        return;
    }

    if (! $pkt->avpacket) {
        warn "didn't get packet";
        return 1;
    }

    my $stream_index = $pkt->stream_index;
    unless (defined $stream_index) {
        warn "didn't get stream index from packet";
        return;
    }

    # don't bother with output if no corresponding output streams
    return 1 unless grep { $_->streams->[$stream_index] }
        @{ $self->output_format_contexts };

    # get input stream
    my $input_stream = $self->input_format_context->get_stream($stream_index);
    unless ($input_stream) {
        warn "Output streams exist for index $stream_index but no input stream with that index was found";
        return 1;
    }

    foreach my $output_ctx (@{ $self->output_format_contexts }) {
        my $output_streams = $output_ctx->streams->[$stream_index];
        next unless $output_streams;

        $_->write_packet($pkt, $input_stream) foreach @$output_streams;
    }

    return 1;
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

Copyright (C) 2011 by Mischa Spiegelmock

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
