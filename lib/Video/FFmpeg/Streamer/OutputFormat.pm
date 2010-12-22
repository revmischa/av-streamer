package Video::FFmpeg::Streamer::OutputFormat;

use Moose;
use namespace::autoclean;
use Video::FFmpeg::Streamer;

use Carp qw/croak/;

# struct AVOutputFormat*
has 'ofmt' => (
    is => 'rw',
    required => 1,
    isa => 'AVOutputFormat',
);

# class method to guess format and return it if found
# takes URI and/or format name
sub find_output_format {
    my ($class, $uri, $format) = @_;

    my $ofmt = Video::FFmpeg::Streamer::ffs_find_output_format($uri, $format);
    return unless $ofmt;

    return $class->new(ofmt => $ofmt);
}

sub DEMOLISH {
    my ($self) = @_;

    warn "demolishing OutputFormat";
}

__PACKAGE__->meta->make_immutable;

