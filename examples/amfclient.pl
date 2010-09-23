#!/usr/bin/env perl -I ./lib -I ../lib

# see http://swxformat.org/php/explorer/

use AMF::Connection;
use HTTP::Cookies;
use Data::Dumper;

my $endpoint = 'http://swxformat.org/php/amf.php';
my $service = 'Flickr';
my $method = 'groupsSearch';

my $client = new AMF::Connection( $endpoint );

$client->setEncoding(3);
#$client->setHTTPProxy('http://127.0.0.1:8888');
$client->addHeader( 'serviceBrowser', 'true' );
$client->setHTTPCookieJar( HTTP::Cookies->new(file => "/tmp/lwpcookies.txt", autosave => 1, ignore_discard => 1 ) );

my $params = [  "italy" ];
my ($response) = $client->call( $service.'.'.$method, $params );

if ( $response->is_success ) {
        print Dumper( $response->getData );
} else {
        die "Can not send remote request for $service.$method method with params on $endpoint\n";
        };

