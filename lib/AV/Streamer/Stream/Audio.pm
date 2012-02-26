package AV::Streamer::Stream::Audio;

use Mouse;
use namespace::autoclean;
use AV::Streamer;

with 'AV::Streamer::Stream';

use Carp qw/croak/;

has 'sample_rate' => (
    is => 'rw',
    isa => 'Int',
);

has 'channels' => (
    is => 'rw',
    isa => 'Int',
);

sub find_encoder {
    my ($self, $codec_name) = @_;

    my $fmt_ctx = $self->format_ctx->avformat;
    
    my $codec;
    if ($self->stream_copy) {
        # jack the codec from the input stream
        $codec = AV::Streamer::avs_get_stream_codec($istream->avstream);
    }

    # look up by codec name
    $codec ||= AV::Streamer::avs_find_audio_encoder($fmt_ctx, $codec_name)
       if $codec_name;
    
    # last resort - try default
    $codec ||= AV::Streamer::avs_find_audio_encoder($fmt_ctx, undef);

    return $codec;
}

sub create_output_avstream {
    my ($self, $istream, $codec) = @_;

    # creates output stream, tries to find and open encoder
    my $oavstream = AV::Streamer::avs_create_output_audio_stream(
        $self->format_ctx->avformat,
        $codec,
    ) or return;

    if ($self->stream_copy) {
        my $ok = AV::Streamer::avs_copy_stream_params($self->format_ctx->avformat, $istream->avstream, $oavstream);
        die "Failed to copy stream params" unless $ok;
    } else {
        my $ok = AV::Streamer::avs_set_audio_stream_params(
            $self->format_ctx->avformat,
            $oavstream,
            $self->codec_name,
            $self->channels,
            $self->sample_rate,
            $self->bit_rate,
        );

        die "failed to set audio stream params" unless $ok;
    }

    return $oavstream;
};

__PACKAGE__->meta->make_immutable;
