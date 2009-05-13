use ExtUtils::MakeMaker;


WriteMakefile
(
    'NAME'		=> 'Net::Server::Mail',
    'VERSION_FROM'	=> 'lib/Net/Server/Mail.pm',
    'PREREQ_PM'		=> {
        "Net::SMTP" => 0,
    },
    ($] >= 5.005 ?
        (
            ABSTRACT_FROM   => 'lib/Net/Server/Mail.pm',
            AUTHOR          => 'Olivier Poitrey <rs@rhapsodyk.net>')
        : ()
    ),
);
