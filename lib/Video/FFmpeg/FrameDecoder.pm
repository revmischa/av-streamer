package Video::FFmpeg::FrameDecoder;

use 5.006000;

use Moose;
use namespace::autoclean;

use Video::FFmpeg::FrameDecoder::AVCodecContext;
use Video::FFmpeg::FrameDecoder::Frame;

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('Video::FFmpeg::FrameDecoder', $VERSION);

# current avformat context
has 'avformat_context' => (
    is => 'rw',
    clearer => 'clear_ctx',
    predicate => 'has_ctx',
);

# list of codecs we have successfully opened
has 'open_codecs' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
);

# URI we are attempting to access
has 'uri' => (
    is => 'rw',
    isa => 'Str',
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
    print "FFmpeg::Video::FrameDecoder: $msg\n";
    return undef;
}

# alias to ctx
sub ctx { $_[0]->avformat_context }

# takes path to file or stream URI
# returns context if success
sub open_uri {
    my ($self, $uri) = @_;

    $self->clear_ctx;
    $self->uri($uri);

    my $ctx = ffv_fd_open_uri($uri);
    if (! $ctx || ! ref $ctx) {
        $self->debug("Failed to open $uri");
        return;
    }
    
    $self->avformat_context($ctx);
    return $ctx;
}

sub close {
    my ($self) = @_;
    
    return unless $self->has_ctx;
    
    $self->open_codecs([]);
    $self->close_context;
}

# look for the first video stream in a file and open the codec for processing.
# returns codec context on success
sub open_video_stream_codec {
    my ($self) = @_;

    # this searches for the first video stream and returns the codec context
    unless ($self->ctx) {
        $self->debug("open_video_codec called but no context found");
        return;
    }

    my $stream_index = ffv_fd_find_first_video_stream_index($self->ctx);
    return $self->debug("open_video_codec failed to find first video stream")
        if $stream_index < 0;
    
    my $_codec_ctx = ffv_fd_get_stream($self->ctx, $stream_index)
        or return $self->debug("open_video_codec get stream $stream_index");

    # find a decoder for the codec and open it for decoding
    unless (ffv_fd_open_codec($_codec_ctx)) {
        $self->debug("open_video_codec failed to open the stream or find a decoder");
        return;
    }

    # we now have an active codec context.
    my $codec_ctx = new Video::FFmpeg::FrameDecoder::AVCodecContext(
        codec_ctx    => $_codec_ctx,
        format_ctx   => $self->ctx,
        stream_index => $stream_index,
    );
    push @{ $self->open_codecs }, $codec_ctx;
    
    $codec_ctx->prepare_video_frame_decoding;

    return $codec_ctx;
}

# dumps debugging information about the current context to stderr
sub dump_format {
    my ($self) = @_;

    return unless $self->has_ctx;

    ffv_fd_dump_format($self->ctx, $self->uri);
}

sub close_context {
    my ($self) = @_;
    
    ffv_fd_destroy_context($self->ctx) if $self->ctx;
    $self->clear_ctx;
}

# do cleanup here
sub DEMOLISH {
    my ($self) = @_;

    $self->close_context;
}

__PACKAGE__->meta->make_immutable;

__END__


=head1 NAME

Video::FFmpeg::FrameDecoder - Module to make processing frames of a
video stream simple.

=head1 SYNOPSIS

  use Moose;
  use Video::FFmpeg::FrameDecoder;
  my $fd = new Video::FFmpeg::FrameDecoder();

  # attempt to access a media stream or file path
  $fd->open_uri('rtsp://10.0.1.2/mpeg4/media.amp')
      or die "Failed to open video stream";
  
  # dump some information about the stream to the console
  $fd->dump_format;

  # locate the first video stream and attempt to find a suitable
  # decoder to open it
  $fd->open_video_stream_codec
      or die "Failed to open video decoder";

  # codecs and stream closed automatically when object is destroyed
  # (can also call $fd->close)
  undef $fd;
  
=head1 DESCRIPTION

This module is based almost wholly on code from Max Vohra's Video::FFmpeg and Martin Boehm's avcodec sample application. It is not an attempt to create anything new or special, but rather to make a simple, moosified structure to make processing video frames easy for people unfamiliar with FFmpeg or XS.

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
