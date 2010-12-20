package Video::FFmpeg::Streamer::Stream;

use Moose;
use namespace::autoclean;
use Video::FFmpeg::Streamer;

use Carp qw/croak/;

=head1 NAME

Video::FFmpeg::Streamer::Stream - Represents an audio or video output
stream.

=cut

has '_stream' => (
    is => 'ro',
    required => 1,
);

has 'index' => (
    is => 'ro',
    isa => 'Int',
    lazy => 1,
    builder => 'build_index',
);

has 'codec_ctx' => (
    is => 'ro',
    builder => 'build_codec_ctx',
    lazy => 1,
);

has 'bit_rate' => (
    is => 'ro',
    isa => 'Int',
);

sub build_codec_ctx {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_get_codec_ctx($self->_stream);
}

sub build_index {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_get_stream_index($self->_stream);
}

=head2 METHODS

=over 4

=item is_video_stream

=cut
sub is_video_stream {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_is_video_stream($self->_stream);
}

=item is_audio_stream

=cut
sub is_audio_stream {
    my ($self) = @_;

    return Video::FFmpeg::Streamer::ffs_is_audio_stream($self->_stream);
}



sub DEMOLISH {
    my ($self) = @_;

    ffs_destroy_stream($self->_stream);
    warn "avstream and codec destroyed";
}

__PACKAGE__->meta->make_immutable;

