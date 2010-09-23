#!/usr/bin/env perl -I ./lib -I ../lib

# see http://code.google.com/p/get-flash-videos/

use AMF::Connection;
use Data::Dumper;

my $endpoint = 'http://c.brightcove.com/services/amfgateway';
my $service = 'com.brightcove.templating.TemplatingFacade';
my $method = 'getContentForTemplateInstance';

my $client = new AMF::Connection( $endpoint );

# $client->config( ... ); # LWP::UserAgent extra params (proxy, auth etc... )

#$client->setEncoding(3);
#$client->setHTTPProxy('http://127.0.0.1:8888');
#$client->setHTTPCookieJar( HTTP::Cookies->new(file => "/tmp/lwpcookies.txt", autosave => 1, ignore_discard => 1 ) );

# eg taken from http://link.brightcove.com/services/player/bcpid46787848001?bctid=14695214001
# works only with AMF0 encoding - at least it seems so - because using openamf ?
#
my $player_id = '46787848001';
my $videoId = '14695214001';

my $params = [
                                                       $player_id, # param 1 - playerId
                                                       {
                                                         'fetchInfos' => [
                                                                           {
                                                                             'fetchLevelEnum' => '1',
                                                                             'contentType' => 'VideoLineup',
                                                                             'childLimit' => '100'
                                                                           },
                                                                           {
                                                                             'fetchLevelEnum' => '3',
                                                                             'contentType' => 'VideoLineupList',
                                                                             'grandchildLimit' => '100',
                                                                             'childLimit' => '100'
                                                                           }
                                                                         ],
                                                         'optimizeFeaturedContent' => 1,
                                                         'lineupRefId' => undef,
                                                         'lineupId' => undef,
                                                         'videoRefId' => undef,
                                                         'videoId' => $videoId, # param 2 - videoId
                                                         'featuredLineupFetchInfo' => {
                                                                                        'fetchLevelEnum' => '4',
                                                                                        'contentType' => 'VideoLineup',
                                                                                        'childLimit' => '100'
                                                                                      }
                                                       }
                                                     ];

my $response = $client->call( $service.'.'.$method, $params );

if ( $response->is_success ) {
	print Dumper( $response->getData );
} else {
	die "Can not send remote request for $service.$method method with params on $endpoint using AMF".$client->getEncoding()." encoding.\n";
	};
