use 5.010000;

use strict;
use warnings;

use lib 'inc';
use ExtUtils::MakeMaker;
use ExtUtils::PkgConfig;

# You will need libavformat-dev, libavcodec-dev and pkg-config

my $lavf_lib = ExtUtils::PkgConfig->libs("libavformat");
my $lavf_inc = ExtUtils::PkgConfig->cflags("libavformat");
die("Installed libavformat version is too low. I require libav 0.8 or greater")
    unless ExtUtils::PkgConfig->atleast_version("libavformat", "53.20.0");

WriteMakefile(
    NAME           => 'AV::Streamer',
    AUTHOR         => 'Mischa Spiegelmock <revmischa@cpan.org>',

    VERSION_FROM   => 'lib/AV/Streamer.pm',
    ABSTRACT_FROM  => 'lib/AV/Streamer.pm',

    PREREQ_PM      => {
        'Mouse' => 0,
        'MouseX::Getopt' => 0,
        'namespace::autoclean' => 0,
        'ExtUtils::PkgConfig' => 0,
    },

    META_ADD => { resources => { repository => 'git://github.com/revmischa/av-streamer.git' } },

    LIBS           => ["-lswscale $lavf_lib"],
    DEFINE         => '',
    INC            => "-I. $lavf_inc",
    OBJECT         => '$(O_FILES)',
);
