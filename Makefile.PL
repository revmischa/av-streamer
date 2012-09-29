use 5.010000;

use strict;
use warnings;

use lib 'inc';
use ExtUtils::MakeMaker;
use ExtUtils::PkgConfig;

# You will need libavformat-dev, libavcodec-dev and pkg-config

# compiler/linker flags for libavformat
die("Installed libavformat version is too low. libav 0.9 or greater required.")
    unless ExtUtils::PkgConfig->atleast_version("libavformat", "54.1.0");
my $lavf_lib = ExtUtils::PkgConfig->libs("libavformat");
my $lavf_inc = ExtUtils::PkgConfig->cflags("libavformat");

# compiler/linker flags for libavcodec
die("Installed libavcodec version is too low. libav 0.9 or greater required.")
    unless ExtUtils::PkgConfig->atleast_version("libavcodec", "54.2.0");
my $lavc_lib = ExtUtils::PkgConfig->libs("libavcodec");
my $lavc_inc = ExtUtils::PkgConfig->cflags("libavcodec");

WriteMakefile(
    NAME           => 'AV::Streamer',
    AUTHOR         => 'Mischa Spiegelmock <revmischa@cpan.org>',

    VERSION_FROM   => 'lib/AV/Streamer.pm',
    ABSTRACT_FROM  => 'lib/AV/Streamer.pm',

    PREREQ_PM      => {
        'Moose' => 0,
        'MooseX::Getopt' => 0,
        'namespace::autoclean' => 0,
        'ExtUtils::PkgConfig' => 0,
    },

    META_ADD => { resources => { repository => 'git://github.com/revmischa/av-streamer.git' } },

    LIBS           => ["-lswscale $lavf_lib $lavc_lib"],
    DEFINE         => '',
    INC            => "-I. $lavf_inc $lavc_inc",
    OBJECT         => '$(O_FILES)',
);
