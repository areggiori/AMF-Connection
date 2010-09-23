package AMF::Connection;

use AMF::Connection::Message;
use AMF::Connection::MessageBody;
use AMF::Connection::OutputStream;
use AMF::Connection::InputStream;

use LWP::UserAgent;
use HTTP::Cookies;

#use Data::Dumper; #for debug

use Carp;
use strict;

our $VERSION = '0.11';

our $HASMD5 = 0;
{
local $@;
eval { require Digest::MD5; };
$HASMD5 = ($@) ? 0 : 1 ;
};

our $HASUUID;
{
local $@;
eval { require Data::UUID; };
$HASUUID = ($@) ? 0 : 1 ;
}

our $HAS_LWP_PROTOCOL_SOCKS;
{
local $@;
eval { require LWP::Protocol::socks };
$HAS_LWP_PROTOCOL_SOCKS = ($@) ? 0 : 1 ;
}

sub new {
	my ($proto, $endpoint) = @_;
        my $class = ref($proto) || $proto;

	my $self = {
		'endpoint' => $endpoint,
		'headers' => [],
		'http_headers' => {},
		'http_cookie_jar' => new HTTP::Cookies(),
		'response_counter' => 0,
		'encoding' => 0, # default is AMF0 encoding
		'ua'	=> new LWP::UserAgent(),
		'append_to_endpoint' => ''
		};

	$self->{'ua'}->cookie_jar( $self->{'http_cookie_jar'} );

        return bless($self, $class);
	};

# plus add paramters, referer, user agent, authentication/credentials ( see also SecureAMFChannel stuff ), 
# plus timezone on retunred dates to pass to de-serializer - see AMF3 spec saying "it is suggested that time zone be queried independnetly as needed" - unelss local DateTime default to right locale!

sub setEndpoint {
	my ($class, $endpoint) = @_;

	$class->{'endpoint'} = $endpoint;
	};

sub getEndpoint {
	my ($class) = @_;

	return $class->{'endpoint'};
	};

sub setHTTPProxy {
	my ($class, $proxy) = @_;

	if(	($proxy =~ m!^socks://(.*?):(\d+)!) &&
		(!$HAS_LWP_PROTOCOL_SOCKS) ) {
		croak "LWP::Protocol::socks is required for SOCKS support";
		};

	$class->{'http_proxy'} = $proxy;

	$class->{'ua'}->proxy( [qw(http https)] => $class->{'http_proxy'} );
	};

sub getHTTPProxy {
	my ($class) = @_;

	return $class->{'http_proxy'};
	};

sub setEncoding {
	my ($class, $encoding) = @_;

	croak "Unsupported AMF encoding $encoding"
		unless( $encoding==0 or $encoding==3 );

	$class->{'encoding'} = $encoding;
	};

sub getEncoding {
	my ($class) = @_;

	return $class->{'encoding'};
	};

sub addHeader {
	my ($class, $header, $value, $required) = @_;

	if( ref($header) ) {
		croak "Not a valid header $header"
			unless( $header->isa("AMF::Connection::MessageHeader") );
	} else {
		$header = new AMF::Connection::MessageHeader( $header, $value, ($required==1) ? 1 : 0  );
		};

	push @{ $class->{'headers'} }, $header;
	};

sub addHTTPHeader {
	my ($class, $name, $value) = @_;

	$class->{'http_headers'}->{ $name } = $value ;
	};

sub setUserAgent {
	my ($class, $ua) = @_;

	croak "Not a valid User-Agent $ua"
		unless( ref($ua) and $ua->isa("LWP::UserAgent") and $ua->can("post") );

	# the passed UA might have a different agent and cookie jar settings
	$class->{'ua'} = $ua;

	# make sure we set the proxy if was already set
	# NOTE - we do not re-check SOCKS support due we assume the setHTTPProxy() was called earlier
	$class->{'ua'}->proxy( [qw(http https)] => $class->{'http_proxy'} )
		if( exists $class->{'http_proxy'} and defined $class->{'http_proxy'} );

	# copy/pass over cookies too
	$class->{'ua'}->cookie_jar( $class->{'http_cookie_jar'} );
	};

sub setHTTPCookieJar {
	my ($class, $cookie_jar) = @_;

	croak "Not a valid cookies jar $cookie_jar"
		unless( ref($cookie_jar) and $cookie_jar->isa("HTTP::Cookies") );

	# TODO - copy/pass over the current cookies (in-memory by default) if any set
	$class->{'http_cookie_jar'}->scan( sub { $cookie_jar->set_cookie( @_ ); } );

	$class->{'http_cookie_jar'} = $cookie_jar;

	# tell user agent to use new cookie jar
        $class->{'ua'}->cookie_jar( $class->{'http_cookie_jar'} );
	};

sub getHTTPCookieJar {
        my ($class) = @_;
		
	return $class->{'http_cookie_jar'};
	};

# send "flex.messaging.messages.RemotingMessage"
sub call {
	my ($class, $command, $arguments ) = @_;

	my $request = new AMF::Connection::Message;
	$request->setEncoding( $class->{'encoding'} );

	# add AMF any request headers
	map { $request->addHeader( $_ ); } @{ $class->{'headers'} };

	# TODO - prepare HTTP/S request headers based on AMF headers received/set if any - and credentials

	my $body = new AMF::Connection::MessageBody;
	$class->{'response_counter'}++;
	$body->setResponse( "/".$class->{'response_counter'} );

	if( $class->{'encoding'} == 3 ) { # AMF3
		$body->setTarget( 'null' );

		my (@command) = split('\.',$command);
		my $method = pop @command;
		my $service = join('.',@command);
		my $remoting_message = $class->_brew_flex_remoting_message( $service, $method, {}, $arguments );

		$body->setData( [ $remoting_message ] ); # it seems we need array ref here - to be checked
	} else {
		$body->setTarget( $command );
		$body->setData( $arguments );
		};

	$request->addBody( $body );

	my $request_stream = new AMF::Connection::OutputStream();

	# serialize request
	$request->serialize($request_stream);

	#print STDERR Dumper( $request );

	# set any extra HTTP header
	map { $class->{'ua'}->default_header( $_ => $class->{'http_headers'}->{$_} ); } keys %{ $class->{'http_headers'} };

	my $http_response = $class->{'ua'}->post(
		$class->{'endpoint'}.$class->{'append_to_endpoint'}, # TODO - check if append to URL this really work for HTTP POST
		Content_Type => "application/x-amf",
		Content => $request_stream->getStreamData()
		);

	croak "HTTP POST error: ".$http_response->status_line."\n"
		unless($http_response->is_success);

	my $response_stream = new AMF::Connection::InputStream( $http_response->content );
	my $response = new AMF::Connection::Message;
	$response->deserialize( $response_stream );

	#print STDERR Dumper( $response )."\n";

	# process AMF response headers
	$class->_process_response_headers( $response );

	my @all;
	map {
		if( $_->getTarget() =~ m|^/$class->{'response_counter'}| ) { # TODO - match the first requested if in a batch
			unshift @all, $_;
		} else {
			push @all, $_;
			};
	} @{ $response->getBodies() };

	# we make sure the main response is always returned first
	return (wantarray) ? @all : $all[0];
	};

# TODO
#
# sub callBatch { }
#
# sub command { } - to send "flex.messaging.messages.CommandMessage" instead
#

sub setCredentials {
	my ($class, $username, $password) = @_;

	$class->addHeader( 'Credentials', { 'userid' => $username,'password' => $password }, 0 );
	};


sub _process_response_headers {
	my ($class,$message) = @_;

	foreach my $header (@{ $message->getHeaders()}) {
		if($header->getName eq 'ReplaceGatewayUrl') { # another way used by server to keep cookies-less sessions
			$class->setEndpoint( $header->getValue )
				unless( ref($header->getValue) );
		} elsif($header->getName eq 'AppendToGatewayUrl') { # generally used for cokies-less sessions E.g. ';jsessionid=99226346ED3FF5296D08146B02ECCA28'
			$class->{'append_to_endpoint'} = $header->getValue
				unless( ref($header->getValue) );
			};
		};
	};

# just an hack to avoid rewrite class mapping local-to-remote and viceversa and make Storable::AMF happy
sub _brew_flex_remoting_message {
        my ($class,$destination,$operation,$headers,$body) = @_;

	return bless( {
		'clientId' => _generateID(),
                'destination' => $destination,
                'messageId' => _generateID(),
                'timestamp' => time() . '00',
                'timeToLive' => 0,
                'headers' => ($headers) ? $headers : {},
                'body' => $body,
                'correlationId' => undef,
                'operation' => $operation,
                'source' => $destination # for backwards compatibility - google for it!
                 }, 'flex.messaging.messages.RemotingMessage' );
        };

sub _generateID {
        my $uniqueid;

        if($HASUUID) {
                eval {
                        my $ug = new Data::UUID;
                        $uniqueid = $ug->to_string( $ug->create() );
                        };
        } elsif ($HASMD5) {
                eval {
                        $uniqueid = substr(Digest::MD5::md5_hex(Digest::MD5::md5_hex(time(). {}. rand(). $$)), 0, 32);
                        };
        } else {
                $uniqueid  ="";
                my $length=16;

                my $j;
                for(my $i=0 ; $i< $length ;) {
                        $j = chr(int(rand(127)));

                        if($j =~ /[a-zA-Z0-9]/) {
                                $uniqueid .=$j;
                                $i++;
                                };
                        };
                };

        return $uniqueid;
        };

1;
__END__

=head1 NAME

AMF::Connection - A simple library to write AMF clients.

=head1 SYNOPSIS

  use AMF::Connection;

  my $endpoint = 'http://myserver.com/flex/amf/'; #AMF server/gateway

  my $service = 'myService';
  my $method = 'myMethod';

  my $client = new AMF::Connection( $endpoint );

  $client->setEncoding(3); # use AMF3 default AMF0

  $client->setHTTPCookieJar( HTTP::Cookies->new(file => "/tmp/mycookies.txt", autosave => 1, ignore_discard => 1 ) );

  my @params = ( 'param1', { 'param2' => 'value2' } );
  my $response = $client->call( "$service.$method", \@params );

  if ( $response->is_success ) {
        my $result_object = $response->getData();
	# ...
  } else {
        die "Can not send remote request for $service.$method method on $endpoint\n";
        };


=head1 DESCRIPTION

I was looking for a simple Perl module to automate data extraction from an existing Flash+Flex/AMS application, and I could not find a decent client implementation. So, this module was born based on available online documentation.

This module has been inspired to SabreAMF PHP implementation of AMF client libraries.

AMF::Connection is meant to provide a simple AMF library to write client applications for invocation of remote services as used by most flex/AIR RIAs. 

The module includes basic support for synchronous HTTP/S based RPC request-response access, where the client sends a request to the server to be processed and the server returns a response to the client containing the processing outcome. Data is sent back and forth in AMF binary format (AMFChannel). Other access patterns such as pub/sub and channels transport are out of scope of this inital release.

AMF0 and AMF3 support is provided using the Storable::AMF module. While HTTP/S requestes to the AMF endpoint are carried out using the LWP::UserAgent module. The requests are sent using the HTTP POST method as AMF0 encoded data by default. AMF3 encoding can be set using the setEncoding() method. Simple AMF3 Externalized Object support is provided on returned objects from the server. Objects returned are simply left in bless( { ... }, 'something') form and they could be mapped to local to the client abstractions if needed. Dates are left encoded as AMF timestamps which represent the number of milliseconds since the epoch (if required DataTime could be used dividing by 1000 the input timestamp and set timezone accordingly). If encoding is set to AMF3 the Flex Messaging framework is used on returned responses content (I.e. objects casted to "flex.messaging.messages.AcknowledgeMessage" and "flex.messaging.messages.ErrorMessage" are returned).

Simple batch requests and responses is provided also.

See the sample usage synopsis above to start using the module.

=head1 METHODS

=head2 new($endpoint)

Create new AMF::Connection object. An endpoint can be specified as the only parameter. Or set in a second moment with the setEndpoint() method.

=head2 call($opeation, $params)

Call the remote service method with given parameters/arguments on the set endpoint and return an AMF::Connection::MessageBody response. Or an array of responses if requsted (wantarray call scope). The $params is generally an array reference, but this version of the AMF::Connection code allows other object types too.

=head2 setEndpoint($endpoint)

Set the AMF service endpoint.

=head2 getEndpoint()

Return the AMF service endpoint.

=head2 setEncoding($encoding)

Set the AMF encoding to use.

=head2 getEncoding()

Return the AMF encoding in use.

=head2 setHTTPProxy($proxy)

Set the HTTP/S proxy to use. If LWP::Protocol is installed SOCKS proxies are supported.

=head2 getHTTPProxy()

Return the HTTP/S procy in use if any.

=head2 addHeader($header[, $value, $required])

Add an AMF AMF::Connection::MessageHeader to the requests. If $header is a string the header value $value and $required flag can be specified.

=head2 addHTTPHeader($name, $value)

Add an HTTP header to sub-sequent HTTP requests.

=head2 setUserAgent($ua)

Allow to specify an alternative LWP::UserAgent. The $ua must support the post() method, proxy() and cookie_jar() if necessary.

=head2 setHTTPCookieJar($cookie_jar)

Allow to specify an alternative HTTP::Cookies jar. By default AMF::Connection keeps cookies into main-memory and the cookie jar is reset when a new connection is created. When a new cookies jar is set, any existing AMF::Connection cookie is copied over.

=head2 getHTTPCookieJar()

Return the current HTTP::Cookies jar in use.

=head2 setCredentials($username,$password)

Minimal support for AMF authentication. Password seems to be wanted in clear.

=head1 SEE ALSO

 AMF::Connection::MessageBody
 Storable::AMF, LWP::UserAgent

 Flex messaging framework / LiveCycle Data Services
  http://livedocs.adobe.com/blazeds/1/javadoc/flex/messaging/io/amf/client/package-summary.html
  http://livedocs.adobe.com/blazeds/1/javadoc/flex/messaging/io/amf/client/AMFConnection.html
  http://www.adobe.com/livedocs/flash/9.0/ActionScriptLangRefV3/flash/net/NetConnection.html
  http://help.adobe.com/en_US/LiveCycleDataServicesES/3.1/Developing/lcds31_using.pdf
  http://help.adobe.com/en_US/Flex/4.0/AccessingData/flex_4_accessingdata.pdf
  http://www.adobe.com/support/documentation/en/livecycledataservices/documentation.html
 
 Specifications
  http://download.macromedia.com/pub/labs/amf/amf0_spec_121207.pdf (AMF0)
  http://opensource.adobe.com/wiki/download/attachments/1114283/amf3_spec_05_05_08.pdf (AMF3)

 SabreAMF
  http://code.google.com/p/sabreamf/

=head1 AUTHOR

Alberto Attilio Reggiori, <areggiori at cpan dot org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Alberto Attilio Reggiori

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
