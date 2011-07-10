use Test::More tests => 4;
use Findbin;
BEGIN { use_ok('AV::Streamer') };

use strict;
use warnings;

my $avs = new AV::Streamer();
my $test_file = "$FindBin::Bin/../sample_mpeg4.mp4";
ok($avs->open_uri($test_file), "opened stream");

$avs->dump_format;

my $codec_ctx = $avs->open_video_stream_codec;
ok($codec_ctx, "opened codec decoder");

my $cb_called;
my $frame_decoded_cb = sub {
    my ($codec_ctx, $frame) = @_;
    
    $cb_called = 1;
};

$codec_ctx->start_decoding(callback => $frame_decoded_cb);
$codec_ctx->decode_frames(1);

ok($cb_called, "Frame decoded and callback called");

undef $avs;

