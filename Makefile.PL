use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'         => 'Net::Server::Mail',
    'VERSION_FROM' => 'lib/Net/Server/Mail.pm',
    'PREREQ_PM'    => {
        'Net::SMTP'       => 0,
        'IO::Socket::SSL' => '1.831',
    },
    'BUILD_REQUIRES' => { 'Test::Most' => 0, },
    (
        $] >= 5.005
        ? (
            ABSTRACT_FROM => 'lib/Net/Server/Mail.pm',
            AUTHOR        => 'Xavier Guimard <x.guimard@free.fr>'
          )
        : ()
    ),
    META_MERGE => {
        resources => {
            repository => 'https://github.com/rs/net-server-mail',
        },
    },
);
