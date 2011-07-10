package AV::FrameDecoder::FrameHandler;

use Moose::Role;
    
use AV::FrameDecoder;

# how many frames to decode, 0 for all
has 'frame_count' => (
    is => 'rw',
    isa => 'Int',
    default => 0,
    cmd_flag => 'framecount',
    cmd_aliases => 'c',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

# input file name or stream URI
has 'stream_uri' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
    cmd_flag => 'input',
    cmd_aliases => 'i',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

has 'output_file_name' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
    cmd_flag => 'output',
    cmd_aliases => 'o',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

has 'dest_bitrate' => (
    is => 'rw',
    isa => 'Int',
    cmd_flag => 'bitrate',
    cmd_aliases => 'b',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

has 'output_format' => (
    is => 'rw',
    isa => 'Str',
    cmd_flag => 'format',
    cmd_aliases => 'f',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

# verbose output, print errors
has 'debug' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
    cmd_aliases => 'd',
    metaclass => 'MooseX::Getopt::Meta::Attribute',
);

# pixel format of destination
has 'dest_pix_format' => (
    is => 'rw',
);

sub run {
    my ($self) = @_;
    
    my $fd = AV::FrameDecoder->new(
        debug => $self->debug,
    );
    
    $fd->open_uri($self->stream_uri)
        or return;
        
    my $codec_ctx = $fd->open_video_stream_codec;
    $codec_ctx->dest_pix_format($self->dest_pix_format)
        if $self->dest_pix_format;
    
    $codec_ctx->start_decoding(
        delegate => $self,
    );
    $codec_ctx->decode_frames($self->frame_count);    
}

####################################################
### required methods
####################################################

requires 'frame_decoded'; # takes $codec_ctx, $frame



####################################################
### optional methods
####################################################

sub decoding_started {
    my ($codec_ctx) = @_;
}

sub decoding_finished {
    my ($codec_ctx) = @_;
}



1;
