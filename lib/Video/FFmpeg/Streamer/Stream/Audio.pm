package Video::FFmpeg::Streamer::Stream::Audio;

use Moose;
use namespace::autoclean;
use Video::FFmpeg::Streamer;

extends 'Video::FFmpeg::Streamer::Stream';

use Carp qw/croak/;

has 'sample_rate' => (
    is => 'rw',
    isa => 'Int',
);

has 'channels' => (
    is => 'rw',
    isa => 'Int',
);

after 'create_avstream' => sub {
    my ($self, $istream) = @_;

    my $oavstream = $self->avstream;

    if ($self->stream_copy) {
        my $ok = Video::FFmpeg::Streamer::ffs_copy_stream_params($self->format_ctx->avformat, $istream->avstream, $oavstream);
        die "Failed to copy stream params" unless $ok;
    } else {
        my $ok = Video::FFmpeg::Streamer::ffs_set_audio_stream_params(
            $self->format_ctx->avformat,
            $oavstream,
            $self->codec_name,
            $self->stream_copy,
            $self->channels,
            $self->sample_rate,
            $self->bit_rate,
        );

        die "failed to set audio stream params" unless $ok;
    }
};

__PACKAGE__->meta->make_immutable;
