use Test::More tests => 4;
use Findbin;
BEGIN { use_ok('Video::FFmpeg::FrameDecoder') };

use strict;
use warnings;

my $fd = new Video::FFmpeg::FrameDecoder();
my $test_file = "$FindBin::Bin/../sample_mpeg4.mp4";
ok($fd->open_uri($test_file), "opened stream");

$fd->dump_format;

my $codec_ctx = $fd->open_video_stream_codec;
ok($codec_ctx, "opened codec decoder");

my $cb_called;
my $frame_decoded_cb = sub {
    my ($frame) = @_;
    
    $cb_called = 1;
};

$codec_ctx->start_decoding(callback => $frame_decoded_cb);
$codec_ctx->decode_frames(1);

ok($cb_called, "Frame decoded and callback called");

undef $fd;

