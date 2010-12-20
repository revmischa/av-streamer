package Video::FFmpeg::Streamer;

use 5.006000;

use Moose;
use namespace::autoclean;

use Video::FFmpeg::Streamer::CodecContext;
use Video::FFmpeg::Streamer::Frame;

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('Video::FFmpeg::Streamer', $VERSION);

has 'input_format_context' => (
    is => 'rw',
    clearer => 'clear_input_format_context',
    predicate => 'has_input_format_context',
);

has 'output_format_contexts' => (
    is => 'rw',
    isa => 'ArrayRef',
    lazy => 1,
    default => sub { [] },
    clearer => 'clear_output_format_contexts',
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

# alias to input ctx
sub input_ctx { $_[0]->input_format_context }

# takes path to file or stream URI
# returns context if success
sub open_uri {
    my ($self, $uri) = @_;

    my $ctx = ffs_open_uri($uri);
    if (! $ctx || ! ref $ctx) {
        $self->debug("Failed to open $uri");
        return;
    }
    
    $self->input_format_context($ctx);
    return $ctx;
}

sub add_output {
    my ($self, $opts) = @_;

    $opts ||= {};
    $opts->{streamer} = $self;

    my $output_ctx = Video::FFmpeg::FormatContext->new($opts);
    push @{$self->output_format_contexts}, $output_ctx;
    return $output_ctx;
}

sub close_input {
    my ($self) = @_;
    
    $self->clear_input_format_context;
}

sub close_outputs {
    my ($self) = @_;
    
    $self->clear_output_format_contexts;
}

__PACKAGE__->meta->make_immutable;

__END__


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
      codec       => 'libfaac',
      sample_rate => 44_100,
      bit_rate    => 64_000,
      channels    => 2,
  });
  $output1->add_video_stream({
      codec    => 'libx264',
      bit_rate => 200_000,
  });

  # begin decoding input and streaming
  $output1->stream;

  # streams closed automatically when object is destroyed
  # (can also call $streamer->close)
  undef $streamer;
  
=head1 DESCRIPTION

This module is based heavily on code from Max Vohra's Video::FFmpeg
and Martin Boehm's avcodec sample application. It is not an attempt to
create anything new or special, but rather to make a simple, moosified
structure to make manipulating streams easy for people unfamiliar with
FFmpeg or XS.

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
