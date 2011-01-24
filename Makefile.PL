use 5.001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Geni',
    VERSION_FROM      => 'lib/Geni.pm', # finds $VERSION
    PREREQ_PM         => { JSON => 2.0 , HTTP::Cookies , IO::Socket::SSL , LWP::UserAgent }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Geni.pm', # retrieve abstract from module
       AUTHOR         => 'Erin Spiceland <erin@thespicelands.com>') : ()),
);
