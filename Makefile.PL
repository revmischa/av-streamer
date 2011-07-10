use 5.010000;

use strict;
use warnings;

use lib 'inc';
use ExtUtils::MakeMaker;
use ExtUtils::PkgConfig;

# You will need libavformat-dev, libavcodec-dev and pkg-config

my $lavf_lib = ExtUtils::PkgConfig->libs("libavformat");
my $lavf_inc = ExtUtils::PkgConfig->cflags("libavformat");
die("Installed libavformat version is too low. I require libav 0.7 or greater")
    unless ExtUtils::PkgConfig->atleast_version("libavformat", "53.0.3");

WriteMakefile(
    NAME           => 'AV::Streamer',
    AUTHOR         => 'Mischa Spiegelmock <revmischa@cpan.org>',

    VERSION_FROM   => 'lib/AV/Streamer.pm',
    ABSTRACT_FROM  => 'lib/AV/Streamer.pm',

    PREREQ_PM      => {
        'MooseX::NonMoose' => 0,
        'MooseX::Getopt' => 0,
        'namespace::autoclean' => 0,
    },

    LIBS           => ["-lswscale $lavf_lib"],
    DEFINE         => '',
    INC            => "-I. $lavf_inc",

	# Un-comment this if you add C files to link with later:
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
