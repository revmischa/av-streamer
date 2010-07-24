use 5.010000;
use ExtUtils::MakeMaker;
use ExtUtils::PkgConfig;

my $lavf_lib = ExtUtils::PkgConfig->libs("libavformat");
my $lavf_inc = ExtUtils::PkgConfig->cflags("libavformat");
die("Installed libavformat version is too low. I require 52.16 or greater") unless (
    ExtUtils::PkgConfig->atleast_version("libavformat", "52.16.0"));

WriteMakefile(
    NAME           => 'Video::FFmpeg::FrameDecoder',
    AUTHOR         => 'Mischa Spiegelmock <revmischa@cpan.org>',

    VERSION_FROM   => 'lib/Video/FFmpeg/FrameDecoder.pm',
    ABSTRACT_FROM  => 'lib/Video/FFmpeg/FrameDecoder.pm',

    PREREQ_PM      => {
        'ExtUtils::PkgConfig' => 0,
        'MooseX::NonMoose' => 0,
        'MooseX::Getopt' => 0,
        'namespace::autoclean' => 0,
        'Video::FFmpeg' => 0,
    },

    LIBS           => ["-lswscale $lavf_lib"],
    DEFINE         => '',
    INC            => "-I. $lavf_inc",

	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
