use Test::More tests => 3;
use Findbin;
BEGIN { use_ok('AV::Streamer') };

use strict;
use warnings;

my $dev_dir = "$FindBin::Bin/../dev";

my $avs = AV::Streamer->new(debug => 1);
my $input_path = "$dev_dir/sample_mpeg4.mp4";
my $output_file = "$dev_dir/test.wmv";
ok($avs->open_uri($input_path), "opened stream $input_path");

my $output1 = $avs->add_output(
    uri => $output_file,
    format => 'wmv',
    real_time => 0,
    bit_rate => 100_000,  # 100Kb/s
);
# $output1->set_metadata('streamName', 'stream1');
# $output1->add_audio_stream(
#     codec_name  => 'wmav1',
#     sample_rate => 44_100,
#     bit_rate    => 64_000,
#     channels    => 2,
# );
$output1->add_video_stream(
    codec_name => 'wmv1',
    bit_rate   => 200_000,
);
$avs->stream;
$avs->close_all;

ok(-e $output_file, "created transcoded file");
unlink($output_file);

undef $avs;

